import CryptoKit
import Foundation

/// Opt-in preparation benchmark. No HTTP server, Apple TV, Keychain or capture.
/// STARTUP_BASELINE links the frozen production sources from 558b235.
@main
struct HLSPreparationPerformanceBenchmark {
    private static let baselineRevision = "558b2350cec9414cfb1d8aca72a693f5412497ef"

    private enum Mode: String, Codable, CaseIterable {
        case baseline, noCache, emptyAppCache, warmAppCache
    }

    private struct InventoryItem: Codable, Equatable {
        let name: String
        let bytes: Int
        let sha256: String
    }

    private struct Sample: Codable {
        let mode: Mode
        let subtitleCodec: String
        let repetition: Int
        let fixtureSHA256: String
        let usedCache: Bool
        let packagedDuration: Double
        let trace: PlaybackStartupTrace.Snapshot
        let servedFiles: [InventoryItem]
    }

    private struct Summary: Codable {
        let baselineRevision: String
        let scope: String
        let limitations: [String]
        let rows: [Row]

        struct Row: Codable {
            let subtitleCodec: String
            let mode: Mode
            let samplesMilliseconds: [Double]
            let medianMilliseconds: Double
            let minimumMilliseconds: Double
            let maximumMilliseconds: Double
        }
    }

    @MainActor
    private final class Recorder {
        var trace = PlaybackStartupTrace()
        var tokens: [PlaybackStartupTrace.Stage: PlaybackStartupTrace.SpanToken] = [:]

        func begin(_ stage: PlaybackStartupTrace.Stage) {
            tokens[stage] = trace.begin(stage, sessionID: trace.sessionID)
        }

        func end(_ stage: PlaybackStartupTrace.Stage) {
            trace.end(tokens.removeValue(forKey: stage), sessionID: trace.sessionID)
        }
    }

    @MainActor
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard let command = arguments.first else { throw Failure("Missing benchmark command") }
        switch command {
        case "fixture":
            guard arguments.count == 4 else { throw Failure("fixture DIRECTORY PINNED_FFMPEG FIXTURE_ENCODER") }
            try await createFixture(
                directory: URL(fileURLWithPath: arguments[1]), ffmpeg: arguments[2], encoder: arguments[3])
        case "run":
            guard arguments.count == 8,
                let mode = Mode(rawValue: arguments[4]), let repetition = Int(arguments[5])
            else { throw Failure("run DIRECTORY FIXTURE CODEC MODE REPETITION FFMPEG FFPROBE") }
            try await measure(
                directory: URL(fileURLWithPath: arguments[1]), input: URL(fileURLWithPath: arguments[2]),
                codec: arguments[3], mode: mode, repetition: repetition,
                ffmpeg: URL(fileURLWithPath: arguments[6]), ffprobe: URL(fileURLWithPath: arguments[7])
            )
        case "summarize":
            guard arguments.count == 3, let repetitions = Int(arguments[2]) else {
                throw Failure("summarize DIRECTORY REPETITIONS")
            }
            try summarize(directory: URL(fileURLWithPath: arguments[1]), repetitions: repetitions)
        default: throw Failure("Unknown benchmark command")
        }
    }

    @MainActor
    private static func measure(
        directory: URL, input: URL, codec: String, mode: Mode, repetition: Int, ffmpeg: URL, ffprobe: URL
    ) async throws {
        guard Executables.find("ffmpeg")?.resolvingSymlinksInPath() == ffmpeg.resolvingSymlinksInPath(),
            BundledEngine.isRequired
        else { throw Failure("Benchmark must resolve only the pinned bundled FFmpeg") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let served = directory.appendingPathComponent("served", isDirectory: true)
        try FileManager.default.createDirectory(at: served, withIntermediateDirectories: false)
        let probe = try await MediaProbeService.probe(url: input, ffprobeURL: ffprobe)
        guard probe.videoCodec == "h264", !probe.isHDR,
            let audio = probe.audioTracks.first, audio.codec == "aac",
            let subtitle = probe.subtitleTracks.first(where: { $0.codec == codec && $0.streamIndex != nil })
        else { throw Failure("Fixture must contain H.264, AAC and embedded \(codec)") }
        let inputHash = hash(try Data(contentsOf: input))
        #if STARTUP_BASELINE
            guard mode == .baseline else { throw Failure("Baseline executable only accepts baseline mode") }
        #else
            guard mode != .baseline else { throw Failure("Current executable does not implement the frozen baseline") }
            let cache =
                mode == .noCache
                ? nil
                : PreparedMediaCache(
                    rootDirectory: directory.appendingPathComponent("cache", isDirectory: true),
                    limitBytes: 256 * 1_024 * 1_024
                )
            if mode == .warmAppCache {
                let warmup = directory.appendingPathComponent("unmeasured-cache-fill", isDirectory: true)
                try FileManager.default.createDirectory(at: warmup, withIntermediateDirectories: false)
                _ = try await HLSPreparationService.prepare(
                    input: input, probe: probe, audio: audio, outputMode: .original,
                    audioDelay: 0, subtitle: subtitle, subtitleDelay: 0.25,
                    outputDirectory: warmup, ffmpegURL: ffmpeg, cache: cache)
                guard let cache, try await cache.sizeBytes() > 0 else { throw Failure("Warmup did not populate cache") }
            } else if let cache, try await cache.sizeBytes() != 0 {
                throw Failure("Empty-app-cache measurement must begin with no retained preparations")
            }
        #endif

        // Probe, fixture generation, cache warmup, hashing and parity checks are
        // outside the measured interval. Both paths finish complete VOD validation.
        let recorder = Recorder()
        let duration: Double
        let usedCache: Bool
        #if STARTUP_BASELINE
            duration = try await prepareBaseline(
                input: input, probe: probe, audio: audio, subtitle: subtitle,
                directory: served, ffmpeg: ffmpeg, recorder: recorder)
            usedCache = false
        #else
            let result = try await HLSPreparationService.prepare(
                input: input, probe: probe, audio: audio, outputMode: .original,
                audioDelay: 0, subtitle: subtitle, subtitleDelay: 0.25,
                outputDirectory: served, ffmpegURL: ffmpeg, cache: cache,
                observer: { event in
                    switch event {
                    case .began(let stage): recorder.begin(stage)
                    case .ended(let stage): recorder.end(stage)
                    default: break
                    }
                })
            duration = result.duration
            usedCache = result.usedCache
            guard usedCache == (mode == .warmAppCache) else { throw Failure("Unexpected preparation cache hit/miss") }
        #endif
        recorder.trace.finish(.prepared, sessionID: recorder.trace.sessionID)
        let snapshot = recorder.trace.snapshot()
        let sample = Sample(
            mode: mode, subtitleCodec: codec, repetition: repetition, fixtureSHA256: inputHash,
            usedCache: usedCache, packagedDuration: duration, trace: snapshot,
            servedFiles: try inventory(served)
        )
        try writeJSON(sample, to: directory.appendingPathComponent("sample.json"))
        print(String(format: "%@ %@ #%d: %.3f ms", codec, mode.rawValue, repetition, snapshot.elapsedSeconds * 1_000))
    }

    #if STARTUP_BASELINE
        /// Preparation portion of StreamCoordinator.beginStreaming at 558b235,
        /// excluding UI labels, local HTTP/AVPlayer and receiver work. Production
        /// packaging, subtitles and validators link from that frozen revision.
        @MainActor
        private static func prepareBaseline(
            input: URL, probe: MediaProbe, audio: AudioTrack, subtitle: SubtitleTrack,
            directory: URL, ffmpeg: URL, recorder: Recorder
        ) async throws -> Double {
            recorder.begin(.packaging)
            let process = Process()
            process.executableURL = ffmpeg
            process.arguments = VODCommandBuilder.arguments(
                input: input, outputDirectory: directory, probe: probe,
                audio: audio, outputMode: .original, audioDelay: 0)
            let errors = Pipe()
            let output = Pipe()
            let log = ProcessLogBuffer()
            let progress = ProcessProgressBuffer()
            errors.fileHandleForReading.readabilityHandler = { handle in
                if let text = String(data: handle.availableData, encoding: .utf8) { log.append(text) }
            }
            output.fileHandleForReading.readabilityHandler = { handle in
                if let text = String(data: handle.availableData, encoding: .utf8) { progress.append(text) }
            }
            process.standardError = errors
            process.standardOutput = output
            let build = VODBuildProcess(
                process: process, log: log, progress: progress, errorPipe: errors, progressPipe: output)
            defer { build.closePipes() }
            try process.run()
            build.didStart()
            let exitTask = Task { try await CancellableProcess(process).waitForExit() }
            defer { exitTask.cancel() }
            while process.isRunning {
                try Task.checkCancellation()
                _ = build.progress.seconds
                _ = build.progress.speed
                try await Task.sleep(for: .milliseconds(200))
            }
            let status = try await exitTask.value
            guard status == 0 else { throw AirCillerError.ffmpegStopped(log.snapshot) }
            build.closePipes()
            try SubtitleService.alignRenditionPlaylists(outputDirectory: directory, expectedDuration: probe.duration)
            recorder.end(.packaging)
            recorder.begin(.subtitles)
            let prepared = try await SubtitleService.prepare(
                track: subtitle, videoURL: input, delay: 0.25,
                videoPlaylistURL: directory.appendingPathComponent("video.m3u8"), outputDirectory: directory)
            try SubtitleService.alignRenditionPlaylists(outputDirectory: directory, expectedDuration: probe.duration)
            recorder.end(.subtitles)
            recorder.begin(.validation)
            try SubtitleService.writeMasterPlaylist(
                probe: probe, audio: audio, audioOutputMode: .original,
                subtitle: prepared, outputDirectory: directory)
            let duration = try SubtitleService.validatePackage(
                outputDirectory: directory, expectedDuration: probe.duration,
                hasAudio: true, hasSubtitles: true)
            _ = try StreamDemandAnalyzer.packagedHLSProfile(outputDirectory: directory, hasSeparateAudio: true)
            recorder.end(.validation)
            return duration
        }
    #endif

    private static func createFixture(directory: URL, ffmpeg: String, encoder: String) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let srt = directory.appendingPathComponent("captions.srt")
        let ass = directory.appendingPathComponent("captions.ass")
        try """
        1
        00:00:01,000 --> 00:00:07,500
        AirCiller benchmark: across a segment boundary.

        2
        00:00:09,000 --> 00:00:16,500
        Second caption: café 日本語 🎵

        """.write(to: srt, atomically: true, encoding: .utf8)
        try """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: 1280
        PlayResY: 720
        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Arial,40,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,8,20,20,20,1
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:01.00,0:00:07.50,Default,,0,0,0,,{\\i1}Styled benchmark{\\i0}\\NSecond line
        Dialogue: 0,0:00:09.00,0:00:16.50,Default,,0,0,0,,{\\an2}Second caption: café 日本語 🎵
        """.write(to: ass, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: encoder)
        process.arguments = [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
            "-f", "lavfi", "-i", "testsrc2=size=1280x720:rate=24:duration=18",
            "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=18",
            "-i", srt.path, "-i", ass.path,
            "-map", "0:v:0", "-map", "1:a:0", "-map", "2:0", "-map", "3:0",
            "-c:v", "libx264", "-preset", "ultrafast", "-crf", "24", "-threads", "1",
            "-pix_fmt", "yuv420p", "-g", "144", "-keyint_min", "144", "-sc_threshold", "0",
            "-c:a", "aac", "-b:a", "128k", "-ac", "2", "-c:s", "copy",
            "-map_metadata", "-1", "-fflags", "+bitexact", "-flags:v", "+bitexact", "-flags:a", "+bitexact",
            "-metadata:s:s:0", "language=eng", "-metadata:s:s:1", "language=eng",
            "-t", "18", directory.appendingPathComponent("encoded-source.mkv").path,
        ]
        process.standardOutput = FileHandle.nullDevice
        let status = try await CancellableProcess(process).run()
        guard status == 0 else { throw Failure("Synthetic fixture generation failed: \(status)") }
        // Only generation uses the explicit development encoder. Remuxing,
        // probing and every measured preparation use the pinned app engine.
        let remux = Process()
        remux.executableURL = URL(fileURLWithPath: ffmpeg)
        remux.arguments = [
            "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
            "-i", directory.appendingPathComponent("encoded-source.mkv").path,
            "-map", "0", "-c", "copy", "-fflags", "+bitexact",
            directory.appendingPathComponent("fixture.mkv").path,
        ]
        remux.standardOutput = FileHandle.nullDevice
        let remuxStatus = try await CancellableProcess(remux).run()
        guard remuxStatus == 0 else { throw Failure("Pinned-engine fixture remux failed: \(remuxStatus)") }
    }

    private static func summarize(directory: URL, repetitions: Int) throws {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            throw Failure("Missing benchmark output")
        }
        var samples: [(Sample, URL)] = []
        for case let url as URL in enumerator where url.lastPathComponent == "sample.json" {
            samples.append(
                (try JSONDecoder().decode(Sample.self, from: Data(contentsOf: url)), url.deletingLastPathComponent()))
        }
        guard samples.count == repetitions * Mode.allCases.count * 2,
            Set(samples.map { $0.0.fixtureSHA256 }).count == 1
        else { throw Failure("Incomplete samples or different fixture input") }
        var rows: [Summary.Row] = []
        for codec in ["subrip", "ass"] {
            guard let reference = samples.first(where: { $0.0.subtitleCodec == codec && $0.0.mode == .baseline }) else {
                throw Failure("Missing baseline")
            }
            for sample in samples where sample.0.subtitleCodec == codec {
                guard sample.0.servedFiles == reference.0.servedFiles,
                    sample.0.packagedDuration == reference.0.packagedDuration
                else { throw Failure("Served output parity failed for \(codec) \(sample.0.mode.rawValue)") }
                for file in sample.0.servedFiles {
                    let relative = "served/\(file.name)"
                    guard
                        try Data(contentsOf: sample.1.appendingPathComponent(relative))
                            == Data(contentsOf: reference.1.appendingPathComponent(relative))
                    else { throw Failure("Byte comparison failed for \(relative)") }
                }
            }
            for mode in Mode.allCases {
                let selected = samples.filter { $0.0.subtitleCodec == codec && $0.0.mode == mode }
                    .map(\.0).sorted { $0.repetition < $1.repetition }
                guard selected.map(\.repetition) == Array(0..<repetitions) else {
                    throw Failure("Missing/duplicate repetition")
                }
                let milliseconds = selected.map { $0.trace.elapsedSeconds * 1_000 }
                let sorted = milliseconds.sorted()
                let median = (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
                rows.append(
                    Summary.Row(
                        subtitleCodec: codec, mode: mode, samplesMilliseconds: milliseconds,
                        medianMilliseconds: median, minimumMilliseconds: sorted[0],
                        maximumMilliseconds: sorted[sorted.count - 1]))
                print(String(format: "%@ %@ median %.3f ms (%d samples)", codec, mode.rawValue, median, repetitions))
            }
        }
        let summary = Summary(
            baselineRevision: baselineRevision,
            scope: "Local complete HLS preparation: embedded text subtitles, copied H.264 and AAC, VOD validation",
            limitations: [
                "Synthetic 18-second SDR fixture, not a large movie or bitmap OCR workload.",
                "A separately fingerprinted development FFmpeg generates the fixture only; remux/probe/preparation use the pinned engine.",
                "Empty app cache does not mean cold OS/disk cache; no system cache purge is performed.",
                "Probe, fixture generation, warm-cache fill and output comparisons are not timed.",
                "No HTTP, receiver, first-visible-frame, sound, HDR or direct-MP4 measurement.",
                "Baseline uses frozen production sources plus the equivalent sequential preparation call order and 200 ms polling.",
                "No performance threshold or expected gain is asserted; every sample must retain identical served bytes.",
            ], rows: rows)
        try writeJSON(summary, to: directory.appendingPathComponent("summary.json"))
        print("All served-file SHA256 inventories and byte-for-byte comparisons match the frozen baseline.")
    }

    private static func inventory(_ directory: URL) throws -> [InventoryItem] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }.map { url in
                guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true,
                    ["m3u8", "m4s", "mp4", "vtt"].contains(url.pathExtension)
                else { throw Failure("Unexpected file in served package: \(url.lastPathComponent)") }
                let data = try Data(contentsOf: url)
                return InventoryItem(name: url.lastPathComponent, bytes: data.count, sha256: hash(data))
            }
    }

    private static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func writeJSON(_ value: some Encodable, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
