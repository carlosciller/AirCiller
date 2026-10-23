import CryptoKit
import Foundation

/// End-to-end authenticated envelope between the private relay and this Mac.
/// This does not replace TLS or MCP caller authentication. The receiver must
/// still admit every mutation through its session-bound command ledger.
struct RemoteCommandEnvelope: Codable, Sendable {
    let operationID: UUID
    let sessionID: UUID
    let expiresAt: Date
    let command: RemoteCommand

    func ledgerRequest() throws -> RemoteCommandLedger.Request {
        .init(
            operationID: operationID, sessionID: sessionID, expiresAt: expiresAt,
            command: try command.validatedEncoding())
    }
}

struct RemoteCommandCipher {
    enum Failure: Error { case invalidKey, oversized, expired, invalidDeadline }
    private let key: SymmetricKey
    private let context: Data
    static let maximumBytes = 24_576

    init(key: Data, installationID: UUID) throws {
        guard key.count == 32 else { throw Failure.invalidKey }
        self.key = SymmetricKey(data: key)
        context = Data(("AirCiller.remote.command.v1:" + installationID.uuidString).utf8)
    }

    func seal(_ envelope: RemoteCommandEnvelope) throws -> Data {
        _ = try envelope.command.validatedEncoding()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let plaintext = try encoder.encode(envelope)
        guard plaintext.count + 28 <= Self.maximumBytes else { throw Failure.oversized }
        // CryptoKit generates a fresh nonce; callers cannot choose or reuse one.
        let box = try AES.GCM.seal(plaintext, using: key, authenticating: context)
        guard let combined = box.combined else { throw Failure.oversized }
        return combined
    }

    func open(_ bytes: Data, now: Date = Date()) throws -> RemoteCommandEnvelope {
        guard bytes.count <= Self.maximumBytes else { throw Failure.oversized }
        let box = try AES.GCM.SealedBox(combined: bytes)
        let plaintext = try AES.GCM.open(box, using: key, authenticating: context)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let envelope = try decoder.decode(RemoteCommandEnvelope.self, from: plaintext)
        let remaining = envelope.expiresAt.timeIntervalSince(now)
        guard remaining.isFinite, remaining <= 60 else { throw Failure.invalidDeadline }
        guard remaining > 0 else { throw Failure.expired }
        _ = try envelope.command.validatedEncoding()
        return envelope
    }
}
