import Foundation

@main
struct CancellableProcessSmokeTest {
    static func main() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let startedAt = ContinuousClock.now
        let task = Task {
            try await CancellableProcess(process).run()
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            _ = try await task.value
            throw NSError(domain: "CancellableProcessSmokeTest.NotCancelled", code: 1)
        } catch is CancellationError {
            // Expected.
        }

        guard !process.isRunning,
            startedAt.duration(to: .now) < .seconds(2)
        else {
            throw NSError(domain: "CancellableProcessSmokeTest.ProcessStillRunning", code: 2)
        }

        let progressProcess = Process()
        progressProcess.executableURL = URL(fileURLWithPath: "/usr/bin/yes")
        progressProcess.standardOutput = FileHandle.nullDevice
        progressProcess.standardError = FileHandle.nullDevice
        try progressProcess.run()
        let waitTask = Task {
            try await CancellableProcess(progressProcess).waitForExit()
        }
        try await Task.sleep(for: .milliseconds(100))
        waitTask.cancel()
        do {
            _ = try await waitTask.value
            throw NSError(domain: "CancellableProcessSmokeTest.WaitNotCancelled", code: 3)
        } catch is CancellationError {
            // Expected.
        }
        guard !progressProcess.isRunning else {
            throw NSError(domain: "CancellableProcessSmokeTest.ProgressStillRunning", code: 4)
        }
        print("Child process and progress observer terminate with their owning tasks: OK")
    }
}
