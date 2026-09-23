import Foundation

@main
struct CapturedProcessSmokeTest {
    static func main() async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for worker in 0..<8 {
                group.addTask {
                    for iteration in 0..<64 {
                        let value = "hello-\(worker)-\(iteration)"
                        let result = try await CapturedProcess.run(
                            executable: URL(fileURLWithPath: "/bin/sh"),
                            arguments: [
                                "-c", "read value; printf 'out:%s' \"$value\"; printf 'err:%s' \"$value\" >&2",
                            ],
                            standardInput: Data("\(value)\n".utf8),
                            maximumOutputBytes: 1_024
                        )
                        try assertCapture(result, output: "out:\(value)", errors: "err:\(value)")
                    }
                }
            }
            try await group.waitForAll()
        }
        try await verifyBoundedOutput()
        try verifyPipeFinalization()
        try verifyReadFailure()

        let failed = try await CapturedProcess.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf partial; printf failure >&2; exit 7"]
        )
        try assertCapture(failed, output: "partial", errors: "failure", status: 7)

        do {
            _ = try await CapturedProcess.run(
                executable: URL(fileURLWithPath: "/AirCillerSmokeTests-missing-executable"), arguments: []
            )
            throw NSError(domain: "CapturedProcessSmokeTest.LaunchSucceeded", code: 4)
        } catch let error as CocoaError {
            guard error.code == .fileNoSuchFile else { throw error }
        }

        let startedAt = ContinuousClock.now
        let task = Task {
            try await CapturedProcess.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                // The descendant keeps stdout/stderr open beyond the deadline.
                arguments: ["-c", "trap '' TERM; sleep 4 & wait"]
            )
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do {
            _ = try await task.value
            throw NSError(domain: "CapturedProcessSmokeTest.NotCancelled", code: 2)
        } catch is CancellationError {
            // Expected.
        }
        guard startedAt.duration(to: .now) < .seconds(2) else {
            throw NSError(domain: "CapturedProcessSmokeTest.SlowCancellation", code: 3)
        }

        print("Captured process: 512 rapid exits, bounded streams, finalization, failures and cancellation: OK")
    }

    private static func verifyBoundedOutput() async throws {
        let outputChunk = "out-" + String(repeating: "0123456789", count: 12)
        let errorChunk = "err-" + String(repeating: "9876543210", count: 12)
        let result = try await CapturedProcess.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: [
                "-c",
                "i=0; while [ \"$i\" -lt 2048 ]; do printf '%s' \"$1\"; printf '%s' \"$2\" >&2; i=$((i+1)); done",
                "capture-test", outputChunk, errorChunk,
            ],
            maximumOutputBytes: 257
        )
        try assertCapture(
            result,
            output: String(String(repeating: outputChunk, count: 2048).suffix(257)),
            errors: String(String(repeating: errorChunk, count: 2048).suffix(257))
        )
        let discarded = try await CapturedProcess.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "printf output; printf error >&2"],
            maximumOutputBytes: 0
        )
        try assertCapture(discarded, output: "", errors: "")
    }

    private static func verifyPipeFinalization() throws {
        let pipe = Pipe()
        let collector = try CapturedProcessPipe(pipe.fileHandleForReading, maximumBytes: 1_024)
        defer { collector.close() }
        // A readiness notification that finds no data must not block or imply EOF.
        collector.readAvailable()
        try pipe.fileHandleForWriting.write(contentsOf: Data("first-".utf8))
        collector.readAvailable()
        try pipe.fileHandleForWriting.write(contentsOf: Data("last".utf8))
        try pipe.fileHandleForWriting.close()
        let result = try collector.finish()
        guard result == Data("first-last".utf8) else {
            throw NSError(domain: "CapturedProcessSmokeTest.FinalDrain", code: 5)
        }
        // Simulate a callback already queued when finalization closed the pipe.
        collector.readAvailable()
        collector.close()
        guard try collector.finish() == result else {
            throw NSError(domain: "CapturedProcessSmokeTest.LateCallback", code: 6)
        }

        let inheritedPipe = Pipe()
        let inherited = try CapturedProcessPipe(inheritedPipe.fileHandleForReading, maximumBytes: 1_024)
        defer { try? inheritedPipe.fileHandleForWriting.close() }
        defer { inherited.close() }
        try inheritedPipe.fileHandleForWriting.write(contentsOf: Data("complete".utf8))
        guard try inherited.finish() == Data("complete".utf8) else {
            throw NSError(domain: "CapturedProcessSmokeTest.OpenWriter", code: 7)
        }
    }

    private static func verifyReadFailure() throws {
        let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null"))
        let collector = try CapturedProcessPipe(handle, maximumBytes: 1_024)
        defer { collector.close() }
        collector.readAvailable()
        do {
            _ = try collector.finish()
            throw NSError(domain: "CapturedProcessSmokeTest.ReadSucceeded", code: 8)
        } catch let error as POSIXError {
            guard error.code == .EBADF else { throw error }
        }
    }

    private static func assertCapture(
        _ result: CapturedProcessResult,
        output: String,
        errors: String,
        status: Int32 = 0
    ) throws {
        let actualOutput = String(decoding: result.output, as: UTF8.self)
        let actualErrors = String(decoding: result.errorOutput, as: UTF8.self)
        guard result.status == status, actualOutput == output, actualErrors == errors else {
            let details =
                "status=\(result.status), stdout=\(actualOutput.debugDescription), stderr=\(actualErrors.debugDescription), "
                + "expected status=\(status), stdout=\(output.debugDescription), stderr=\(errors.debugDescription)"
            FileHandle.standardError.write(Data("Capture mismatch: \(details)\n".utf8))
            throw NSError(
                domain: "CapturedProcessSmokeTest.Capture", code: 1,
                userInfo: [NSLocalizedDescriptionKey: details]
            )
        }
    }
}
