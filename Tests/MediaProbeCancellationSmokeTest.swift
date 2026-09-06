import Darwin
import Foundation

@main
@MainActor
struct MediaProbeCancellationSmokeTest {
    static func main() async throws {
        // A private FIFO keeps the real bundled ffprobe busy without a large movie or network input.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AirCiller-ProbeCancel-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fifo = root.appendingPathComponent("input.mkv")
        guard mkfifo(fifo.path, 0o600) == 0,
            let engine = ProcessInfo.processInfo.environment["AIRCILLER_TEST_FFPROBE"]
        else { throw Failure.setup }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) { _exit(2) }
        for replace in [false, true] {
            let tasks = MediaAnalysisTasks()
            let started = AsyncStream<Process>.makeStream()
            var cancelled = false
            var unexpectedResult = false
            let task = Task {
                do {
                    _ = try await MediaProbeService.probe(url: fifo, ffprobeURL: URL(fileURLWithPath: engine)) {
                        started.continuation.yield($0)
                    }
                    unexpectedResult = true
                } catch is CancellationError { cancelled = true } catch { unexpectedResult = true }
            }
            tasks.replacePrimary(with: task)
            var iterator = started.stream.makeAsyncIterator()
            guard let process = await iterator.next(), process.isRunning else { throw Failure.notRunning }
            let began = ContinuousClock.now
            if replace { tasks.replacePrimary(with: Task {}) } else { tasks.cancelAll() }
            await task.value
            started.continuation.finish()
            guard cancelled, !unexpectedResult, !process.isRunning,
                began.duration(to: .now) < .seconds(3)
            else { throw Failure.cancellation }
            tasks.cancelAll()
        }
        print("Real bundled ffprobe: Stop and analysis replacement reap the running child within three seconds: OK")
    }

    private enum Failure: Error { case setup, notRunning, cancellation }
}
