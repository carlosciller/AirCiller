import CryptoKit
import Foundation

@main
@MainActor
struct DirectCachePerformanceBenchmark {
    static func main() async throws {
        let args = CommandLine.arguments
        let root = URL(fileURLWithPath: args[1], isDirectory: true)
        let input = URL(fileURLWithPath: args[2])
        let subtitles = URL(fileURLWithPath: args[3])
        let ffmpeg = URL(fileURLWithPath: args[4])
        let ffprobe = URL(fileURLWithPath: args[5])
        let iterations = args.count > 6 ? Int(args[6]) ?? 0 : 3
        guard (1...3).contains(iterations) else { throw Failure.cache }
        let info = try await MediaProbeService.probe(url: input, ffprobeURL: ffprobe)
        let subtitle = MediaProbeService.externalTrack(url: subtitles)
        func arguments(_ directory: URL) -> [String] {
            DirectFileCommandBuilder.arguments(
                input: input, output: directory.appendingPathComponent("movie.mp4"), probe: info,
                audio: info.audioTracks.first, outputMode: .original, audioDelay: 0,
                subtitle: subtitle, subtitleDelay: 0)
        }
        let key = try PreparedMediaCache.makeDirectKey(
            source: input, engineURL: ffmpeg,
            arguments: arguments(URL(fileURLWithPath: "/")), subtitleInputs: [subtitles])
        let original = try hash(input)
        var rows: [[String: Any]] = []
        var reference: String?
        for iteration in 0..<iterations {
            let cache = PreparedMediaCache(
                rootDirectory: root.appendingPathComponent("cache-\(iteration)"), limitBytes: 16 * 1_024 * 1_024 * 1_024
            )
            for mode in (iteration % 2 == 0 ? ["disabled", "empty", "warm"] : ["empty", "warm", "disabled"]) {
                let directory = root.appendingPathComponent("\(iteration)-\(mode)")
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                let began = ContinuousClock.now
                var built = false
                let result = try await DirectPreparationCache.prepare(
                    directory: directory, cache: mode == "disabled" ? nil : cache, key: key,
                    build: {
                        built = true
                        let process = Process()
                        process.executableURL = ffmpeg
                        process.arguments = arguments(directory)
                        process.standardOutput = FileHandle.nullDevice
                        process.standardError = FileHandle.nullDevice
                        guard try await CancellableProcess(process).run() == 0 else { throw Failure.mux }
                    },
                    validate: {
                        let prepared = try await MediaProbeService.probe(
                            url: directory.appendingPathComponent("movie.mp4"), ffprobeURL: ffprobe)
                        guard prepared.videoCodec == info.videoCodec,
                            abs(prepared.duration - info.duration) < 0.2,
                            prepared.audioTracks.first?.codec == info.audioTracks.first?.codec,
                            prepared.subtitleTracks.count == 1
                        else { throw Failure.metadata }
                        return prepared
                    })
                if mode != "disabled", !result.usedCache { _ = try await cache.store(key: key, from: directory) }
                let duration = began.duration(to: .now).components
                let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
                let digest = try hash(directory.appendingPathComponent("movie.mp4"))
                if let reference, reference != digest { throw Failure.bytes }
                reference = digest
                guard result.usedCache == (mode == "warm"), built == (mode != "warm") else { throw Failure.cache }
                rows.append([
                    "iteration": iteration, "mode": mode, "seconds": seconds,
                    "usedCache": result.usedCache, "sha256": digest,
                ])
            }
            try await cache.clear()
            for mode in ["disabled", "empty", "warm"] {
                try FileManager.default.removeItem(at: root.appendingPathComponent("\(iteration)-\(mode)"))
            }
        }
        guard try original == hash(input) else { throw Failure.bytes }
        let data = try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("measurement.json"))
        print(String(decoding: data, as: UTF8.self))
    }

    private static func hash(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private enum Failure: Error { case mux, metadata, bytes, cache }
}
