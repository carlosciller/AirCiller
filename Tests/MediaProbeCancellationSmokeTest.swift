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
        let helper = root.appendingPathComponent("selective-probe")
        try """
        #!/bin/sh
        case "$*" in
          *-select_streams*) exec /bin/sleep 30;;
          *) printf '%s' '{"streams":[{"index":0,"codec_type":"video","codec_name":"hevc"}],"format":{"duration":"1"}}';;
        esac
        """.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let started = AsyncStream<Process>.makeStream()
        let selectedProbe = Task {
            try await MediaProbeService.probe(url: root.appendingPathComponent("fake.mkv"), ffprobeURL: helper) {
                started.continuation.yield($0)
            }
        }
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
        guard let second = await iterator.next(), second.isRunning else { throw Failure.notRunning }
        selectedProbe.cancel()
        do {
            _ = try await selectedProbe.value
            throw Failure.cancellation
        } catch is CancellationError {}
        started.continuation.finish()
        guard !second.isRunning else { throw Failure.cancellation }
        print("Real bundled ffprobe: Stop and analysis replacement reap the running child within three seconds: OK")
        print("Selected-video extradata probe is cancelled and reaped independently: OK")
    }

    private enum Failure: Error { case setup, notRunning, cancellation }
}
