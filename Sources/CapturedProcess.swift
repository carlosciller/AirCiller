import Darwin
import Foundation

struct CapturedProcessResult: Sendable {
    let output: Data
    let errorOutput: Data
    let status: Int32
}

/// Runs a short-lived child process with bounded output and structured cancellation.
enum CapturedProcess {
    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]? = nil,
        standardInput: Data? = nil,
        maximumOutputBytes: Int = 1_048_576
    ) async throws -> CapturedProcessResult {
        let process = Process()
        let input = standardInput == nil ? nil : Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = input ?? FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = errors

        let outputCollector = try CapturedProcessPipe(output.fileHandleForReading, maximumBytes: maximumOutputBytes)
        defer { outputCollector.close() }
        let errorCollector = try CapturedProcessPipe(errors.fileHandleForReading, maximumBytes: maximumOutputBytes)
        defer { errorCollector.close() }
        outputCollector.start()
        errorCollector.start()

        do {
            let status = try await CancellableProcess(process).run {
                try? output.fileHandleForWriting.close()
                try? errors.fileHandleForWriting.close()
                if let standardInput, let input {
                    try? input.fileHandleForWriting.write(contentsOf: standardInput)
                    try? input.fileHandleForWriting.close()
                }
            }
            return CapturedProcessResult(
                output: try outputCollector.finish(),
                errorOutput: try errorCollector.finish(),
                status: status
            )
        } catch {
            try? input?.fileHandleForWriting.close()
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForWriting.close()
            throw error
        }
    }
}

/// Serializes each read with its append and final snapshot. Nonblocking reads
/// also let cancellation close a pipe whose write end a descendant still owns.
final class CapturedProcessPipe: @unchecked Sendable {
    private let handle: FileHandle
    private let descriptor: Int32
    private let buffer: ProcessDataBuffer
    private let lock = NSLock()
    private var closed = false
    private var readError: Error?

    init(_ handle: FileHandle, maximumBytes: Int) throws {
        self.handle = handle
        descriptor = handle.fileDescriptor
        buffer = ProcessDataBuffer(maximumBytes: maximumBytes)
        let flags = fcntl(descriptor, F_GETFL)
        guard flags != -1, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    func start() {
        handle.readabilityHandler = { [weak self] _ in self?.readAvailable() }
    }

    func readAvailable() {
        lock.withLock {
            guard !closed, readError == nil else { return }
            do {
                if try readChunk() == 0 { handle.readabilityHandler = nil }
            } catch {
                readError = error
                handle.readabilityHandler = nil
            }
        }
    }

    func finish() throws -> Data {
        handle.readabilityHandler = nil
        return try lock.withLock {
            guard !closed else { return buffer.snapshot }
            defer { closeLocked() }
            if let readError { throw readError }
            // The owned process has exited. Drain its buffered output without
            // waiting for later writes from independently running descendants.
            while try readChunk() > 0 { try Task.checkCancellation() }
            return buffer.snapshot
        }
    }

    func close() {
        handle.readabilityHandler = nil
        lock.withLock { closeLocked() }
    }

    private func closeLocked() {
        guard !closed else { return }
        closed = true
        try? handle.close()
    }

    /// Returns 0 at EOF and -1 when the open pipe has no available bytes.
    private func readChunk() throws -> Int {
        var bytes = [UInt8](repeating: 0, count: 16_384)
        while true {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                buffer.append(Data(bytes.prefix(count)))
                return count
            }
            if count == 0 { return 0 }
            let code = errno
            if code == EINTR { continue }
            if code == EAGAIN || code == EWOULDBLOCK { return -1 }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
    }
}
