import Foundation

/// Research-only partial guard; missing extensions can bypass these messages.
/// Sticky, bounded evidence across the entire stderr stream. A successful exit
/// cannot erase a decoder recovery that substituted lossy DTS core samples.
final class LosslessDecoderGuard: @unchecked Sendable {
    enum Failure: String, Sendable { case recovery, oversizedRead }
    private let lock = NSLock()
    private var suffix = Data()
    private var recordedFailure: Failure?
    private static let signatures = [
        Data("Invalid XLL sync word".utf8),
        Data("Forcing XLL recovery mode".utf8),
    ]
    private static let retainedBytes = (signatures.map(\.count).max() ?? 1) - 1

    @discardableResult
    func append(_ data: Data) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard recordedFailure == nil else { return false }
        guard data.count <= 1_048_576 else {
            recordedFailure = .oversizedRead
            suffix.removeAll()
            return false
        }
        var combined = suffix
        combined.append(data)
        if Self.signatures.contains(where: { combined.range(of: $0) != nil }) {
            recordedFailure = .recovery
            suffix.removeAll()
            return false
        }
        suffix = Data(combined.suffix(Self.retainedBytes))
        return true
    }

    var failure: Failure? {
        lock.lock()
        defer { lock.unlock() }
        return recordedFailure
    }
}
