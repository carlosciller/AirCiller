import Foundation

/// Admission control for authenticated remote commands. The coordinator owns
/// session changes; a transport must never create a session on the caller's behalf.
@MainActor
final class RemoteCommandLedger {
    struct Request: Equatable, Sendable {
        let operationID: UUID
        let sessionID: UUID
        let expiresAt: Date
        // Canonical, validated command encoding, not raw JSON from the network.
        let command: Data
    }

    enum State: Equatable, Sendable {
        case accepted
        case preparing
        case awaitingDecision
        case completed
        case failed(String)
        case cancelled
    }

    enum Admission: Equatable {
        case execute
        case replay(State)
        case reject(Rejection)
    }

    enum Rejection: Equatable {
        case staleSession
        case expired
        case invalidDeadline
        case conflictingOperation
        case capacity
        case invalidCommand
    }

    private struct Entry {
        let request: Request
        var state: State
    }

    private(set) var sessionID = UUID()
    private var entries: [UUID: Entry] = [:]
    private let capacity: Int

    init(capacity: Int = 1_024, sessionID: UUID = UUID()) {
        precondition(capacity > 0)
        self.capacity = capacity
        self.sessionID = sessionID
    }

    /// Rotate on a new media selection, Stop, disable, or process restart.
    /// Old commands then fail even after their deduplication entries are gone.
    func beginSession(_ sessionID: UUID = UUID()) {
        self.sessionID = sessionID
        entries.removeAll(keepingCapacity: true)
    }

    func admit(_ request: Request, now: Date = Date()) -> Admission {
        guard request.sessionID == sessionID else { return .reject(.staleSession) }
        if let previous = entries[request.operationID] {
            guard previous.request == request else { return .reject(.conflictingOperation) }
            return .replay(previous.state)
        }
        let lifetime = request.expiresAt.timeIntervalSince(now)
        guard lifetime.isFinite else { return .reject(.invalidDeadline) }
        guard lifetime > 0 else { return .reject(.expired) }
        guard lifetime <= 60 else { return .reject(.invalidDeadline) }
        guard !request.command.isEmpty, request.command.count <= 16_384 else {
            return .reject(.invalidCommand)
        }
        // Never evict a live session's accepted operations: retrying an evicted
        // relative seek could apply it twice. Fail closed when the budget is full.
        guard entries.count < capacity else { return .reject(.capacity) }
        entries[request.operationID] = Entry(request: request, state: .accepted)
        return .execute
    }

    @discardableResult
    func update(operationID: UUID, sessionID: UUID, state: State) -> Bool {
        guard sessionID == self.sessionID, var entry = entries[operationID] else { return false }
        switch entry.state {
        case .completed, .failed, .cancelled: return false
        case .accepted, .preparing, .awaitingDecision: break
        }
        entry.state = state
        entries[operationID] = entry
        return true
    }

    func state(operationID: UUID, sessionID: UUID) -> State? {
        guard sessionID == self.sessionID else { return nil }
        return entries[operationID]?.state
    }
}
