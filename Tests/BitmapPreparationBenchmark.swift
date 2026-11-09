import CryptoKit
import Foundation

@main
struct BitmapPreparationBenchmark {
    static func main() async throws {
        let args = CommandLine.arguments
        let source = URL(fileURLWithPath: args[1])
        let root = URL(fileURLWithPath: args[2])
        let probe = try await MediaProbeService.probe(url: source)
        guard let track = probe.subtitleTracks.first(where: \.usesBitmapOCR) else { throw Failure.noTrack }
        let timing = Timing()
        let began = Date()
        let cold = try await PGSSubtitleConverter.convert(
            track: track, videoURL: source, videoDuration: probe.duration,
            cacheDirectory: root.appendingPathComponent("cache"),
            progress: { completed, total in
                timing.record(completed: completed, total: total)
            })
        let coldSeconds = Date().timeIntervalSince(began)
        let warmStart = Date()
        let warm = try await PGSSubtitleConverter.convert(
            track: track, videoURL: source, videoDuration: probe.duration,
            cacheDirectory: root.appendingPathComponent("cache"))
        let warmSeconds = Date().timeIntervalSince(warmStart)
        guard !cold.usedCache, warm.usedCache, cold.webVTT == warm.webVTT else { throw Failure.parity }
        let firstProgress = timing.firstProgress
        let report: [String: Any] = [
            "codec": track.codec, "duration": probe.duration, "cues": cold.cueCount,
            "groups": timing.total, "coldSeconds": coldSeconds, "warmSeconds": warmSeconds,
            "extractionAndGroupingSeconds": firstProgress?.timeIntervalSince(began) ?? -1,
            "recognitionAndWriteSeconds": firstProgress.map {
                began.addingTimeInterval(coldSeconds).timeIntervalSince($0)
            } ?? -1,
            "identicalWebVTT": true,
            "webVTTSHA256": SHA256.hash(data: Data(cold.webVTT.utf8)).map { String(format: "%02x", $0) }.joined(),
            "scope": "Full track, isolated empty/warm subtitle cache; no receiver; OS cache uncontrolled",
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("measurement.json"))
        print(String(decoding: data, as: UTF8.self))
    }

    private enum Failure: Error { case noTrack, parity }
    private final class Timing: @unchecked Sendable {
        private let lock = NSLock()
        private var first: Date?
        private var count = 0
        func record(completed: Int, total: Int) {
            lock.lock()
            defer { lock.unlock() }
            if first == nil { first = Date() }
            count = total
        }
        var firstProgress: Date? {
            lock.lock()
            defer { lock.unlock() }
            return first
        }
        var total: Int {
            lock.lock()
            defer { lock.unlock() }
            return count
        }
    }
}
