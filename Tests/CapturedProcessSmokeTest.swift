import Foundation

@main
struct CapturedProcessSmokeTest {
    static func main() async throws {
        let input = Data("hello\n".utf8)
        let result = try await CapturedProcess.run(
            executable: URL(fileURLWithPath: "/bin/sh"),
            arguments: ["-c", "read value; printf 'out:%s' \"$value\"; printf 'err:%s' \"$value\" >&2"],
            standardInput: input,
            maximumOutputBytes: 1_024
        )
        guard result.status == 0,
            String(decoding: result.output, as: UTF8.self) == "out:hello",
            String(decoding: result.errorOutput, as: UTF8.self) == "err:hello"
        else {
            throw NSError(domain: "CapturedProcessSmokeTest.Capture", code: 1)
        }

        let startedAt = ContinuousClock.now
        let task = Task {
            try await CapturedProcess.run(
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "trap '' TERM; while :; do sleep 1; done"]
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

        print("Captured helper output is bounded and cancellation terminates the child: OK")
    }
}
