import CryptoKit
import Darwin
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
        let fixtureBytes: Int64
        let resources: Resources
        let storage: Storage
        let usedCache: Bool
        let packagedDuration: Double
        let trace: PlaybackStartupTrace.Snapshot
        let servedFiles: [InventoryItem]
    }

    private struct Resources: Codable {
        let selfCPUSeconds: Double
        let childrenCPUSeconds: Double
        let sampledSelfPeakRSSBytes: UInt64
        let sampledChildrenPeakRSSBytes: UInt64
        let sampledAggregatePeakRSSBytes: UInt64
        let rssSamples: Int
        let rssReadFailures: Int
        let requestedRSSIntervalMilliseconds: Int
    }

    private struct Storage: Codable {
        let servedLogicalBytes: Int64
        let retainedCacheLogicalBytes: Int64
        let generatedSampleLogicalBytes: Int64
        let uniqueInodeLogicalBytes: Int64
    }

    private struct ParityProof: Codable {
        let referenceSampleSHA256: String
        let sampleSHA256: String
        let comparedFiles: Int
        let comparedBytes: Int64
    }

    @MainActor
    private final class ResourceMonitor {
        private let initialSelf: Double
        private let initialChildren: Double
        private var selfPeak: UInt64 = 0
        private var childrenPeak: UInt64 = 0
        private var aggregatePeak: UInt64 = 0
        private var samples = 0
        private var failures = 0
        private var samplingTask: Task<Void, Never>?

        init() throws {
            initialSelf = try Self.cpu(RUSAGE_SELF)
            initialChildren = try Self.cpu(RUSAGE_CHILDREN)
            sample()
            samplingTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .milliseconds(20)) } catch { break }
                    self?.sample()
                }
            }
        }

        func cancel() { samplingTask?.cancel() }

        func finish() async throws -> Resources {
            samplingTask?.cancel()
            await samplingTask?.value
            samplingTask = nil
            sample()
            return Resources(
                selfCPUSeconds: max(0, try Self.cpu(RUSAGE_SELF) - initialSelf),
                childrenCPUSeconds: max(0, try Self.cpu(RUSAGE_CHILDREN) - initialChildren),
                sampledSelfPeakRSSBytes: selfPeak, sampledChildrenPeakRSSBytes: childrenPeak,
                sampledAggregatePeakRSSBytes: aggregatePeak, rssSamples: samples,
                rssReadFailures: failures, requestedRSSIntervalMilliseconds: 20)
        }

        private static func cpu(_ who: Int32) throws -> Double {
            var usage = rusage()
            guard getrusage(who, &usage) == 0 else { throw Failure("Cannot read benchmark CPU accounting") }
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }

        private func residentBytes(_ pid: pid_t) -> UInt64? {
            var info = proc_taskinfo()
            let count = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
            guard count == MemoryLayout<proc_taskinfo>.size else {
                failures += 1
                return nil
            }
            return info.pti_resident_size
        }

        private func sample() {
            samples += 1
            let own = residentBytes(getpid()) ?? 0
            // Only this benchmark's direct children are queried. PIDs and
            // command lines are neither retained nor exported.
            var children = [pid_t](repeating: 0, count: 64)
            let count = children.withUnsafeMutableBytes {
                proc_listchildpids(getpid(), $0.baseAddress, Int32($0.count))
            }
            var childRSS: UInt64 = 0
            if count < 0 {
                failures += 1
            } else {
                // Unlike proc_listpids, this wrapper returns a PID count.
                // Apple libproc divides the underlying byte count itself.
                for pid in children.prefix(min(children.count, Int(count))) where pid > 0 {
                    childRSS += residentBytes(pid) ?? 0
                }
            }
            selfPeak = max(selfPeak, own)
            childrenPeak = max(childrenPeak, childRSS)
            aggregatePeak = max(aggregatePeak, own + childRSS)
        }
    }

    private struct Summary: Codable {
        let baselineRevision: String
        let fixtureBytes: Int64
        let packagedDuration: Double
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
            let medianSelfCPUSeconds: Double
            let medianChildrenCPUSeconds: Double
            let maximumSampledAggregateRSSBytes: UInt64
            let rssReadFailures: Int
            let servedLogicalBytes: Int64
            let retainedCacheLogicalBytes: Int64
            let uniqueInodeLogicalBytes: Int64
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
        case "resource-self-test":
            guard arguments.count == 2 else { throw Failure("resource-self-test OUTPUT_JSON") }
            let monitor = try ResourceMonitor()
            defer { monitor.cancel() }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = ["0.2"]
            let status = try await CancellableProcess(process).run()
            let result = try await monitor.finish()
            guard status == 0, result.sampledSelfPeakRSSBytes > 0,
                result.sampledChildrenPeakRSSBytes > 0, result.rssSamples >= 2
            else { throw Failure("Resource monitor failed to observe its own controlled child process") }
            try writeJSON(result, to: URL(fileURLWithPath: arguments[1]))
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
        case "verify":
            guard arguments.count == 3 else { throw Failure("verify REFERENCE_DIRECTORY SAMPLE_DIRECTORY") }
            try verifySample(
                reference: URL(fileURLWithPath: arguments[1]), candidate: URL(fileURLWithPath: arguments[2]))
        case "discard-generated-packages":
            guard arguments.count == 2 else { throw Failure("discard-generated-packages SAMPLE_DIRECTORY") }
            let directory = URL(fileURLWithPath: arguments[1])
            _ = try JSONDecoder().decode(
                ParityProof.self, from: Data(contentsOf: directory.appendingPathComponent("parity.json")))
            _ = try JSONDecoder().decode(
                Sample.self, from: Data(contentsOf: directory.appendingPathComponent("sample.json")))
            for name in ["served", "cache"] {
                let target = directory.appendingPathComponent(name, isDirectory: true)
                if FileManager.default.fileExists(atPath: target.path) {
                    try FileManager.default.removeItem(at: target)
                }
            }
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
        let inputHash = try hashFile(input)
        let inputBytes = try logicalBytes(input)
        #if STARTUP_BASELINE
            guard mode == .baseline else { throw Failure("Baseline executable only accepts baseline mode") }
        #else
            guard mode != .baseline else { throw Failure("Current executable does not implement the frozen baseline") }
            let cache =
                mode == .noCache
                ? nil
                : PreparedMediaCache(
                    rootDirectory: directory.appendingPathComponent("cache", isDirectory: true),
                    limitBytes: 8 * 1_024 * 1_024 * 1_024
                )
            if mode == .warmAppCache {
                let warmup = directory.appendingPathComponent("unmeasured-cache-fill", isDirectory: true)
                try FileManager.default.createDirectory(at: warmup, withIntermediateDirectories: false)
                _ = try await HLSPreparationService.prepare(
                    input: input, probe: probe, audio: audio, outputMode: .original,
                    audioDelay: 0, subtitle: subtitle, subtitleDelay: 0.25,
                    outputDirectory: warmup, ffmpegURL: ffmpeg, cache: cache)
                guard let cache, try await cache.sizeBytes() > 0 else { throw Failure("Warmup did not populate cache") }
                // Remove only this newly generated session; cache hard links
                // retain its base. Warmup is excluded from time and disk totals.
                try FileManager.default.removeItem(at: warmup)
            } else if let cache, try await cache.sizeBytes() != 0 {
                throw Failure("Empty-app-cache measurement must begin with no retained preparations")
            }
        #endif

        // Probe, fixture generation, cache warmup, hashing and parity checks are
        // outside the measured interval. Both paths finish complete VOD validation.
        let monitor = try ResourceMonitor()
        defer { monitor.cancel() }
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
        let resources = try await monitor.finish()
        let sample = Sample(
            mode: mode, subtitleCodec: codec, repetition: repetition, fixtureSHA256: inputHash,
            fixtureBytes: inputBytes, resources: resources, storage: try storage(directory),
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
            guard
                let reference = samples.first(where: {
                    $0.0.subtitleCodec == codec && $0.0.mode == .baseline && $0.0.repetition == 0
                })
            else {
                throw Failure("Missing baseline")
            }
            for sample in samples where sample.0.subtitleCodec == codec {
                guard sample.0.servedFiles == reference.0.servedFiles,
                    sample.0.packagedDuration == reference.0.packagedDuration
                else { throw Failure("Served output parity failed for \(codec) \(sample.0.mode.rawValue)") }
                let proof = try JSONDecoder().decode(
                    ParityProof.self, from: Data(contentsOf: sample.1.appendingPathComponent("parity.json")))
                guard
                    proof.referenceSampleSHA256
                        == hash(try Data(contentsOf: reference.1.appendingPathComponent("sample.json"))),
                    proof.sampleSHA256 == hash(try Data(contentsOf: sample.1.appendingPathComponent("sample.json"))),
                    proof.comparedFiles == sample.0.servedFiles.count,
                    proof.comparedBytes == sample.0.servedFiles.reduce(Int64(0), { $0 + Int64($1.bytes) })
                else { throw Failure("Missing/stale byte-parity proof") }
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
                        maximumMilliseconds: sorted[sorted.count - 1],
                        medianSelfCPUSeconds: medianValue(selected.map { $0.resources.selfCPUSeconds }),
                        medianChildrenCPUSeconds: medianValue(selected.map { $0.resources.childrenCPUSeconds }),
                        maximumSampledAggregateRSSBytes: selected.map { $0.resources.sampledAggregatePeakRSSBytes }
                            .max() ?? 0,
                        rssReadFailures: selected.reduce(0) { $0 + $1.resources.rssReadFailures },
                        servedLogicalBytes: selected[0].storage.servedLogicalBytes,
                        retainedCacheLogicalBytes: selected[0].storage.retainedCacheLogicalBytes,
                        uniqueInodeLogicalBytes: selected[0].storage.uniqueInodeLogicalBytes))
                print(String(format: "%@ %@ median %.3f ms (%d samples)", codec, mode.rawValue, median, repetitions))
            }
        }
        let summary = Summary(
            baselineRevision: baselineRevision,
            fixtureBytes: samples[0].0.fixtureBytes,
            packagedDuration: samples[0].0.packagedDuration,
            scope: "Local complete HLS preparation: embedded text subtitles, copied H.264 and AAC, VOD validation",
            limitations: [
                "Synthetic SDR H.264/AAC fixture (size and duration recorded), not a private movie or bitmap OCR workload.",
                "A separately fingerprinted development FFmpeg generates the fixture only; remux/probe/preparation use the pinned engine.",
                "Empty app cache does not mean cold OS/disk cache; no system cache purge is performed.",
                "Probe, fixture generation, warm-cache fill and output comparisons are not timed.",
                "No HTTP, receiver, first-visible-frame, sound, HDR or direct-MP4 measurement.",
                "Baseline uses frozen production sources plus the equivalent sequential preparation call order and 200 ms polling.",
                "No performance threshold or expected gain is asserted; every sample must retain identical served bytes.",
                "CPU is the preparation-interval rusage delta for this benchmark and its reaped children, including measurement overhead.",
                "RSS is sampled every requested 20 ms for this benchmark and its direct children; short peaks can be missed and shared mappings can be counted twice.",
                "Storage is end-of-preparation logical size, with a second total deduplicating hard-linked inodes; it is not peak or physical allocated disk space.",
                "Cache warmup finishes and its disposable session is removed before measurement; only retained cache and measured session enter storage totals.",
                "Byte comparisons run before any generated package cleanup. Per-sample proofs remain linked to the exact sample JSON hashes.",
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
                return InventoryItem(
                    name: url.lastPathComponent, bytes: Int(try logicalBytes(url)), sha256: try hashFile(url))
            }
    }

    private static func medianValue(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
    }

    private static func logicalBytes(_ file: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
            let bytes = attributes[.size] as? NSNumber
        else { throw Failure("Expected regular generated media file") }
        return bytes.int64Value
    }

    private static func storage(_ directory: URL) throws -> Storage {
        var sizes: [String: Int64] = [:]
        var unique: [String: Int64] = [:]
        for name in ["served", "cache"] {
            let root = directory.appendingPathComponent(name, isDirectory: true)
            var total: Int64 = 0
            if FileManager.default.fileExists(atPath: root.path) {
                guard
                    let files = FileManager.default.enumerator(
                        at: root, includingPropertiesForKeys: [.isRegularFileKey])
                else {
                    throw Failure("Cannot inventory generated sample storage")
                }
                for case let url as URL in files {
                    guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
                    var attributes = stat()
                    guard lstat(url.path, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG else {
                        throw Failure("Cannot stat generated sample file")
                    }
                    total += attributes.st_size
                    unique["\(attributes.st_dev):\(attributes.st_ino)"] = attributes.st_size
                }
            }
            sizes[name] = total
        }
        return Storage(
            servedLogicalBytes: sizes["served", default: 0], retainedCacheLogicalBytes: sizes["cache", default: 0],
            generatedSampleLogicalBytes: sizes.values.reduce(0, +), uniqueInodeLogicalBytes: unique.values.reduce(0, +))
    }

    private static func hashFile(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let finished = try autoreleasepool {
                guard let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty else { return true }
                hasher.update(data: chunk)
                return false
            }
            if finished { break }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func verifySample(reference: URL, candidate: URL) throws {
        let referenceData = try Data(contentsOf: reference.appendingPathComponent("sample.json"))
        let sampleData = try Data(contentsOf: candidate.appendingPathComponent("sample.json"))
        let expected = try JSONDecoder().decode(Sample.self, from: referenceData)
        let sample = try JSONDecoder().decode(Sample.self, from: sampleData)
        guard expected.mode == .baseline, expected.repetition == 0,
            sample.subtitleCodec == expected.subtitleCodec, sample.fixtureSHA256 == expected.fixtureSHA256,
            sample.packagedDuration == expected.packagedDuration, sample.servedFiles == expected.servedFiles
        else { throw Failure("Preparation or served inventory differs from baseline") }
        for file in expected.servedFiles {
            let first = try FileHandle(forReadingFrom: reference.appendingPathComponent("served/\(file.name)"))
            let second = try FileHandle(forReadingFrom: candidate.appendingPathComponent("served/\(file.name)"))
            defer {
                try? first.close()
                try? second.close()
            }
            var hasher = SHA256()
            var count = 0
            while true {
                let bytes = try autoreleasepool {
                    let one = try first.read(upToCount: 1_048_576) ?? Data()
                    let two = try second.read(upToCount: 1_048_576) ?? Data()
                    guard one == two else { throw Failure("Byte parity failed: \(file.name)") }
                    hasher.update(data: one)
                    return one.count
                }
                if bytes == 0 { break }
                count += bytes
            }
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard count == file.bytes, digest == file.sha256 else {
                throw Failure("Served file changed before comparison")
            }
        }
        try writeJSON(
            ParityProof(
                referenceSampleSHA256: hash(referenceData), sampleSHA256: hash(sampleData),
                comparedFiles: sample.servedFiles.count,
                comparedBytes: sample.servedFiles.reduce(0) { $0 + Int64($1.bytes) }),
            to: candidate.appendingPathComponent("parity.json"))
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
