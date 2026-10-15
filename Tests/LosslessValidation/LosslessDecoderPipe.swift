import Darwin
import Foundation

/// Research-only pipe ownership; diagnostic signatures do not prove losslessness.
/// One serialized reader owns stderr through EOF. Recovery cannot hide in the
/// final pipe bytes after the process's termination notification.
final class LosslessDecoderPipe: @unchecked Sendable {
    private let handle: FileHandle
    private let descriptor: Int32
    private let log: ProcessLogBuffer
    private let guardState = LosslessDecoderGuard()
    private let onRejection: @Sendable () -> Void
    private let lock = NSLock()
    private var source: DispatchSourceRead?
    private var closed = false
    private var reachedEOF = false
    private var readFailed = false
    private var rejectionSent = false

    init(handle: FileHandle, log: ProcessLogBuffer, onRejection: @escaping @Sendable () -> Void) throws {
        self.handle = handle
        self.descriptor = handle.fileDescriptor
        self.log = log
        self.onRejection = onRejection
        let flags = fcntl(descriptor, F_GETFL)
        guard flags != -1, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, source == nil else { return }
        let reader = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .global(qos: .utility))
        reader.setEventHandler { [weak self] in self?.readAvailable() }
        source = reader
        reader.resume()
    }

    /// Called after joining the child and closing the parent's write end.
    /// EAGAIN is not EOF and cannot certify a complete diagnostic stream.
    func finish() -> Bool {
        lock.lock()
        source?.cancel()
        source = nil
        if !closed { drainLocked() }
        let accepted = reachedEOF && !readFailed && guardState.failure == nil
        closeLocked()
        lock.unlock()
        return accepted
    }

    func close() {
        lock.lock()
        closeLocked()
        lock.unlock()
    }

    deinit { close() }

    private func readAvailable() {
        lock.lock()
        if !closed { drainLocked() }
        let reject = (readFailed || guardState.failure != nil) && !rejectionSent
        if reject { rejectionSent = true }
        lock.unlock()
        if reject { onRejection() }
    }

    private func drainLocked() {
        var bytes = [UInt8](repeating: 0, count: 16_384)
        while !reachedEOF, !readFailed {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                let data = Data(bytes.prefix(count))
                guardState.append(data)
                log.append(String(decoding: data, as: UTF8.self))
            } else if count == 0 {
                reachedEOF = true
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                return
            } else {
                readFailed = true
            }
        }
    }

    private func closeLocked() {
        guard !closed else { return }
        closed = true
        source?.cancel()
        source = nil
        try? handle.close()
    }
}
