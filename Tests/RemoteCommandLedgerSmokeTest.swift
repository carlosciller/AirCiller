import Foundation

@main
struct RemoteCommandLedgerSmokeTest {
    @MainActor
    static func main() {
        let ledger = RemoteCommandLedger(capacity: 2)
        let now = Date(timeIntervalSince1970: 1_000)
        let session = ledger.sessionID
        func request(
            id: UUID = UUID(), sessionID: UUID? = nil,
            deadline: Double = 30, command: String = "skip:30"
        ) -> RemoteCommandLedger.Request {
            .init(
                operationID: id, sessionID: sessionID ?? ledger.sessionID,
                expiresAt: now.addingTimeInterval(deadline), command: Data(command.utf8))
        }
        let first = request()
        precondition(ledger.admit(first, now: now) == .execute)
        precondition(ledger.admit(first, now: now) == .replay(.accepted))
        precondition(
            ledger.admit(request(id: first.operationID, command: "next"), now: now)
                == .reject(.conflictingOperation))
        precondition(ledger.update(operationID: first.operationID, sessionID: session, state: .completed))
        precondition(!ledger.update(operationID: first.operationID, sessionID: session, state: .preparing))
        precondition(ledger.admit(first, now: now.addingTimeInterval(90)) == .replay(.completed))
        precondition(ledger.admit(request(deadline: 0), now: now) == .reject(.expired))
        precondition(ledger.admit(request(deadline: 61), now: now) == .reject(.invalidDeadline))
        precondition(ledger.admit(request(command: ""), now: now) == .reject(.invalidCommand))
        let second = request(command: "pause")
        precondition(ledger.admit(second, now: now) == .execute)
        precondition(ledger.update(operationID: second.operationID, sessionID: session, state: .cancelled))
        precondition(ledger.admit(request(), now: now) == .reject(.capacity))
        precondition(ledger.admit(first, now: now) == .replay(.completed))
        ledger.beginSession()
        precondition(ledger.admit(first, now: now) == .reject(.staleSession))
        precondition(ledger.state(operationID: first.operationID, sessionID: session) == nil)
        precondition(!ledger.update(operationID: first.operationID, sessionID: session, state: .completed))
        precondition(ledger.admit(request(), now: now) == .execute)
        print("Remote command ledger: OK")
    }
}
