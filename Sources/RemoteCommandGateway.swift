import Foundation

/// Serialized app-side boundary, before any transport is enabled. Authentication
/// failure returns no state or library information. It does not log raw errors.
@MainActor
final class RemoteCommandGateway {
    enum Failure: Error { case deliveryIdentityMismatch }
    struct Response: Codable, Sendable {
        let operationID: UUID
        let disposition: String
        let code: String?
        let snapshot: RemotePlaybackControl.Snapshot
        let items: [RemoteLibraryIndex.Item]?
        let tracks: [RemotePlaybackControl.Track]?
        let receivers: [RemotePlaybackControl.Receiver]?
        let preferences: RemotePlaybackControl.Preferences?
    }

    private let cipher: RemoteCommandCipher
    private let control: RemotePlaybackControl
    private let ledger: RemoteCommandLedger
    private struct Operation {
        let command: RemoteCommand
        let requestSessionID: UUID
        let sessionID: UUID
        let startedAt: Date
        var terminal: String?
    }
    private var operations: [UUID: Operation] = [:]
    private var cancellableOperationID: UUID?

    private func operationState(_ id: UUID) -> String? {
        guard var operation = operations[id] else { return nil }
        if let terminal = operation.terminal { return terminal }
        let current = control.snapshot()
        let state: String
        if current.sessionID != operation.sessionID {
            state = "superseded"
        } else if current.phase == "error" {
            state = "failed"
        } else if current.awaitingConversion {
            return "awaiting_decision"
        } else if current.phase == "analyzing" || current.phase == "preparing" {
            return "preparing"
        } else {
            let fresh = (current.receiverObservedAt ?? 0) >= operation.startedAt.timeIntervalSince1970
            switch operation.command {
            case .pause: state = fresh && current.phase == "paused" ? "receiver_confirmed" : "accepted"
            case .resume, .play, .next, .selectTracks, .synchronize, .resolveConversion:
                state = fresh && current.phase == "playing" ? "receiver_confirmed" : "accepted"
            case .seek(let target):
                state =
                    fresh && current.position.map { abs($0 - target) <= 2 } == true
                    ? "receiver_confirmed" : "accepted"
            case .skip: state = fresh ? "receiver_updated" : "accepted"
            default: state = "completed_locally"
            }
        }
        if state != "accepted" {
            operation.terminal = state
            operations[id] = operation
        }
        return state
    }

    init(coordinator: StreamCoordinator, installationID: UUID, key: Data) throws {
        cipher = try RemoteCommandCipher(key: key, installationID: installationID)
        control = RemotePlaybackControl(coordinator: coordinator, installationKey: key)
        ledger = RemoteCommandLedger(sessionID: coordinator.remoteControlSessionID)
    }

    func receive(
        _ authenticatedBytes: Data, expectedOperationID: UUID? = nil, now: Date = Date()
    ) throws -> Response {
        let envelope = try cipher.open(authenticatedBytes, now: now)
        // Correlate transport identity before dispatch. Checking the response
        // afterwards is too late for commands such as Stop or relative seek.
        guard expectedOperationID == nil || expectedOperationID == envelope.operationID else {
            throw Failure.deliveryIdentityMismatch
        }
        let snapshot = control.snapshot()
        if ledger.sessionID != snapshot.sessionID { ledger.beginSession(snapshot.sessionID) }
        func response(
            _ disposition: String, code: String? = nil,
            items: [RemoteLibraryIndex.Item]? = nil,
            tracks: [RemotePlaybackControl.Track]? = nil,
            receivers: [RemotePlaybackControl.Receiver]? = nil,
            preferences: RemotePlaybackControl.Preferences? = nil
        ) -> Response {
            Response(
                operationID: envelope.operationID, disposition: disposition, code: code,
                snapshot: control.snapshot(), items: items, tracks: tracks,
                receivers: receivers, preferences: preferences)
        }
        // Authenticated status bootstraps the current session. All other commands
        // must use the identity returned by a fresh status response.
        if envelope.command == .status { return response("result") }
        guard envelope.sessionID == snapshot.sessionID else { return response("rejected", code: "stale_session") }
        switch envelope.command {
        case .search(let query): return response("result", items: try control.search(query))
        case .tracks: return response("result", tracks: control.tracks())
        case .receivers: return response("result", receivers: control.receivers())
        case .preferences: return response("result", preferences: control.preferences())
        case .operation(let id):
            guard let state = operationState(id) else {
                return response("rejected", code: "unknown_operation")
            }
            return response("result", code: state)
        default: break
        }
        guard envelope.command.mutates else { return response("rejected", code: "unsupported_command") }
        if let previous = operations[envelope.operationID] {
            guard previous.command == envelope.command, previous.requestSessionID == envelope.sessionID else {
                return response("rejected", code: "operation_conflict")
            }
            return response("duplicate", code: "not_executed_again")
        }
        guard operations.count < 1024 || operations[envelope.operationID] != nil else {
            return response("rejected", code: "operation_capacity")
        }
        switch ledger.admit(try envelope.ledgerRequest(), now: now) {
        case .reject(let reason): return response("rejected", code: String(describing: reason))
        case .replay: return response("duplicate", code: "not_executed_again")
        case .execute: break
        }
        // Retain failures and cancellation requests too. Session rotation must
        // never permit an old operation ID to execute a second mutation.
        operations[envelope.operationID] = Operation(
            command: envelope.command,
            requestSessionID: envelope.sessionID, sessionID: snapshot.sessionID, startedAt: now)
        do {
            if case .cancelOperation(let id) = envelope.command {
                guard cancellableOperationID == id, let operation = operations[id],
                    operation.sessionID == snapshot.sessionID,
                    ["accepted", "preparing", "awaiting_decision"].contains(operationState(id) ?? "")
                else {
                    operations[envelope.operationID]?.terminal = "operation_not_cancellable"
                    return response("rejected", code: "operation_not_cancellable")
                }
                try control.dispatch(.stop, sessionID: envelope.sessionID)
                operations[id]?.terminal = "cancelled"
                cancellableOperationID = nil
                operations[envelope.operationID]?.terminal = "cancelled_locally"
                return response("accepted", code: "cancelled_locally")
            }
            try control.dispatch(envelope.command, sessionID: envelope.sessionID)
            operations[envelope.operationID] = Operation(
                command: envelope.command,
                requestSessionID: envelope.sessionID, sessionID: control.snapshot().sessionID, startedAt: now)
            // Declining a conversion and editing an idle item's settings do not
            // start receiver playback. They must not wait forever for it.
            switch envelope.command {
            case .resolveConversion(_, false, _):
                operations[envelope.operationID]?.terminal = "declined"
            case .selectTracks, .synchronize:
                if control.snapshot().phase == "idle" {
                    operations[envelope.operationID]?.terminal = "completed_locally"
                }
            default: break
            }
            switch envelope.command {
            case .play, .next, .selectTracks, .synchronize, .resolveConversion:
                cancellableOperationID = operations[envelope.operationID]?.terminal == nil ? envelope.operationID : nil
            case .stop: cancellableOperationID = nil
            default: break
            }
            // Acceptance is intentionally not completion or receiver confirmation.
            return response("accepted")
        } catch let failure as RemotePlaybackControl.Failure {
            let code = String(describing: failure)
            operations[envelope.operationID]?.terminal = code
            ledger.update(operationID: envelope.operationID, sessionID: envelope.sessionID, state: .failed(code))
            return response("rejected", code: code)
        } catch {
            operations[envelope.operationID]?.terminal = "invalid_command"
            ledger.update(
                operationID: envelope.operationID, sessionID: envelope.sessionID,
                state: .failed("invalid_command"))
            return response("rejected", code: "invalid_command")
        }
    }
}
