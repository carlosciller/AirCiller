import Foundation

@main
struct RemoteCommandEnvelopeSmokeTest {
    @MainActor
    static func main() throws {
        let installation = UUID()
        let key = Data(repeating: 3, count: 32)
        let cipher = try RemoteCommandCipher(key: key, installationID: installation)
        let now = Date(timeIntervalSince1970: 1_000)
        let ledger = RemoteCommandLedger()
        let envelope = RemoteCommandEnvelope(
            operationID: UUID(), sessionID: ledger.sessionID,
            expiresAt: now.addingTimeInterval(30), command: .skip(seconds: 30))
        let sealed = try cipher.seal(envelope)
        let decoded = try cipher.open(sealed, now: now)
        precondition(decoded.command == envelope.command && decoded.operationID == envelope.operationID)
        let request = try decoded.ledgerRequest()
        precondition(ledger.admit(request, now: now) == .execute)
        precondition(ledger.admit(request, now: now) == .replay(.accepted))
        let otherCipher = try RemoteCommandCipher(key: Data(repeating: 4, count: 32), installationID: installation)
        let otherInstallation = try RemoteCommandCipher(key: key, installationID: UUID())
        func reject(_ action: () throws -> Void) {
            do {
                try action()
                preconditionFailure("Unauthenticated or invalid envelope accepted")
            } catch {}
        }
        reject { _ = try otherCipher.open(sealed, now: now) }
        reject { _ = try otherInstallation.open(sealed, now: now) }
        var changed = sealed
        changed[changed.startIndex] ^= 1
        reject { _ = try cipher.open(changed, now: now) }
        reject { _ = try cipher.open(sealed, now: now.addingTimeInterval(31)) }
        reject { _ = try cipher.open(sealed, now: now.addingTimeInterval(-31)) }
        reject { _ = try cipher.open(Data(repeating: 0, count: 24_577), now: now) }
        reject { _ = try cipher.open(Data(), now: now) }
        reject { _ = try RemoteCommandCipher(key: Data(), installationID: installation) }
        let anotherSeal = try cipher.seal(envelope)
        precondition(anotherSeal != sealed)
        ledger.beginSession()
        precondition(ledger.admit(request, now: now) == .reject(.staleSession))
        print("Remote encrypted envelope, tamper rejection and replay admission: OK")
    }
}
