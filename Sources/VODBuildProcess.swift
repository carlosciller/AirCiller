import Darwin
import Foundation

final class VODBuildProcess: @unchecked Sendable {
    let process: Process
    let log: ProcessLogBuffer
    let progress: ProcessProgressBuffer
    private let errorPipe: Pipe
    private let progressPipe: Pipe
    private let strictDiagnostics: StrictDecoderDiagnostics?

    init(
        process: Process,
        log: ProcessLogBuffer,
        progress: ProcessProgressBuffer,
        errorPipe: Pipe,
        progressPipe: Pipe,
        strictDiagnostics: StrictDecoderDiagnostics? = nil
    ) {
        self.process = process
        self.log = log
        self.progress = progress
        self.errorPipe = errorPipe
        self.progressPipe = progressPipe
        self.strictDiagnostics = strictDiagnostics
    }

    func closePipes() {
        strictDiagnostics?.close()
        errorPipe.fileHandleForReading.readabilityHandler = nil
        progressPipe.fileHandleForReading.readabilityHandler = nil
        try? errorPipe.fileHandleForReading.close()
        try? progressPipe.fileHandleForReading.close()
    }

    func didStart() {
        strictDiagnostics?.start()
        try? errorPipe.fileHandleForWriting.close()
        try? progressPipe.fileHandleForWriting.close()
    }

    /// Joined children must also supply a complete, clean diagnostic stream.
    func finishStrictDecoding() -> Bool {
        strictDiagnostics?.finish() ?? true
    }
}

/// Used only with FFmpeg's warning/error logging for explicit TrueHD → FLAC.
/// Decoder errors can be logged while FFmpeg exits successfully. Keep sticky
/// evidence, including final bytes, across decoder warnings and errors.
final class StrictDecoderDiagnostics: @unchecked Sendable {
    private let handle: FileHandle
    private let descriptor: Int32
    private let log: ProcessLogBuffer
    private let lock = NSLock()
    private var reader: DispatchSourceRead?
    private var started = false
    private var closed = false
    private var reachedEOF = false
    private var readFailed = false
    private var policy = StrictDecoderDiagnosticPolicy()

    init(handle: FileHandle, log: ProcessLogBuffer) throws {
        self.handle = handle
        self.descriptor = handle.fileDescriptor
        self.log = log
        let flags = fcntl(descriptor, F_GETFL)
        guard flags != -1, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard !closed, !started else { return }
        started = true
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .global(qos: .utility))
        source.setEventHandler { [weak self] in self?.readAvailable() }
        reader = source
        source.resume()
    }

    func finish() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if !closed { drainLocked() }
        let accepted = !closed && reachedEOF && !readFailed && policy.finish()
        closeLocked()
        return accepted
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        closeLocked()
    }

    deinit { close() }

    private func readAvailable() {
        lock.lock()
        defer { lock.unlock() }
        if !closed { drainLocked() }
    }

    private func drainLocked() {
        var bytes = [UInt8](repeating: 0, count: 16_384)
        while !reachedEOF, !readFailed {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                let data = Data(bytes.prefix(count))
                policy.append(data)
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
        reader?.cancel()
        reader = nil
        try? handle.close()
    }
}

/// The pinned HLS muxer warns about FLAC's empty final packet. Complete sample
/// and timestamp regressions establish that this exact mux warning loses no
/// audio. Never apply its exception to decoder warnings or unknown messages.
struct StrictDecoderDiagnosticPolicy {
    private var pending = Data()
    private var failed = false

    mutating func append(_ data: Data) {
        guard !failed else { return }
        for byte in data {
            if byte == 10 {
                inspectLine()
                pending.removeAll(keepingCapacity: true)
                if failed { return }
            } else {
                pending.append(byte)
                if pending.count > 2_048 {
                    failed = true
                    pending.removeAll()
                    return
                }
            }
        }
    }

    mutating func finish() -> Bool {
        if !pending.isEmpty { inspectLine() }
        pending.removeAll()
        return !failed
    }

    private mutating func inspectLine() {
        guard let line = String(data: pending, encoding: .utf8) else {
            failed = true
            return
        }
        if line.isEmpty { return }
        let knownMuxWarning =
            "^\\[hls @ 0x[0-9a-fA-F]+\\] Stream 0 packet with pts [0-9]{1,19} has duration 0\\. The segment duration may not be precise\\.$"
        if line.range(of: knownMuxWarning, options: .regularExpression) == nil { failed = true }
    }
}

final class ProcessProgressBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var pending = ""
    private var latestSeconds = 0.0
    private var latestSpeed: Double?

    func append(_ value: String) {
        lock.lock()
        pending.append(value)
        let lines = pending.components(separatedBy: "\n")
        pending = lines.last ?? ""
        for line in lines.dropLast() {
            if line.hasPrefix("out_time_us="),
                let microseconds = Double(line.dropFirst("out_time_us=".count))
            {
                latestSeconds = max(latestSeconds, microseconds / 1_000_000)
            } else if line.hasPrefix("speed=") {
                let value = line.dropFirst("speed=".count).trimmingCharacters(in: .whitespaces)
                latestSpeed = Double(
                    value.trimmingCharacters(in: CharacterSet(charactersIn: "x"))
                )
            }
        }
        lock.unlock()
    }

    var seconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return latestSeconds
    }

    var speed: Double? {
        lock.lock()
        defer { lock.unlock() }
        return latestSpeed
    }
}

final class ProcessLogBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ value: String) {
        lock.lock()
        text.append(value)
        if text.count > 8_000 { text = String(text.suffix(8_000)) }
        lock.unlock()
    }

    var snapshot: String {
        lock.lock()
        defer { lock.unlock() }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
