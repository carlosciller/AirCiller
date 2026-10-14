import Darwin
import Foundation

/// Opt-in, receiver-free invocation of the production HLS preparation service.
/// Arguments: synthetic movie, new output directory, pinned engine bin, mode.
@main
struct PCMHLSMediaSmokeTest {
    static func main() async throws {
        do {
            try await run()
        } catch AirCillerError.probeFailed(let detail) {
            FileHandle.standardError.write(Data("Probe rejection: \(detail)\n".utf8))
            exit(2)
        } catch AirCillerError.ffmpegStopped(let detail) {
            FileHandle.standardError.write(Data("FFmpeg rejection: \(detail)\n".utf8))
            exit(3)
        }
    }

    private static func run() async throws {
        guard [5, 6, 7].contains(CommandLine.arguments.count),
            let mode = AudioOutputMode(rawValue: CommandLine.arguments[4])
        else { throw Failure.invalidArguments }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let engine = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: output.path) else { throw Failure.invalidArguments }
        let probe = try await MediaProbeService.probe(url: input, ffprobeURL: engine.appendingPathComponent("ffprobe"))
        guard let audio = probe.audioTracks.first else { throw Failure.noAudio }
        FileHandle.standardError.write(
            Data(
                "PCM probe: \(audio.codec), bits=\(audio.bitsPerSample ?? 0), rate=\(audio.sampleRate ?? 0), layout=\(audio.channelLayout ?? "unknown"), eligible=\(audio.canPrepareLosslessFLAC)\n"
                    .utf8))
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let extraArguments = Array(CommandLine.arguments.dropFirst(5))
        if let clockExperiment = extraArguments.first(where: { $0.hasPrefix("--clock-") }) {
            guard probe.duration <= 12, mode == .losslessFLAC, audio.canPrepareLosslessFLAC,
                ["--clock-default", "--clock-disabled", "--clock-negative-cts", "--clock-combined"].contains(
                    clockExperiment)
            else { throw Failure.invalidArguments }
            var arguments = VODCommandBuilder.arguments(
                input: input, outputDirectory: output, probe: probe, audio: audio,
                outputMode: mode, audioDelay: 0)
            if ["--clock-disabled", "--clock-combined"].contains(clockExperiment) {
                arguments = arguments.map { $0 == "make_zero" ? "disabled" : $0 }
            }
            if ["--clock-negative-cts", "--clock-combined"].contains(clockExperiment) {
                for index in arguments.indices.reversed() where arguments[index] == "-f" {
                    arguments.insert(contentsOf: ["-hls_segment_options", "movflags=+negative_cts_offsets"], at: index)
                }
            }
            let process = Process()
            process.executableURL = engine.appendingPathComponent("ffmpeg")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.standardError
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw Failure.invalidManifest }
            print("{\"clock_experiment\":\"\(clockExperiment)\",\"receiver_tested\":false}")
            return
        }
        let cache = extraArguments.first(where: { $0 != "--no-subtitles" }).map {
            PreparedMediaCache(rootDirectory: URL(fileURLWithPath: $0), limitBytes: 1_000_000_000)
        }
        let result = try await HLSPreparationService.prepare(
            input: input, probe: probe, audio: audio, outputMode: mode, audioDelay: 0,
            subtitle: extraArguments.contains("--no-subtitles") ? nil : probe.subtitleTracks.first,
            subtitleDelay: 0, outputDirectory: output,
            ffmpegURL: engine.appendingPathComponent("ffmpeg"), cache: cache)
        // Container duration includes edit-list / leading presentation offsets.
        // Packet-level timing and complete sample retention are checked independently
        // by validate_pcm_hls.py, including the declared VOD decode span.
        guard result.duration.isFinite, result.duration > 0 else {
            throw Failure.invalidDuration
        }
        let master =
            probe.isHDR
            ? "" : try String(contentsOf: output.appendingPathComponent("master.m3u8"), encoding: .utf8)
        if mode == .losslessFLAC && !probe.isHDR {
            guard audio.canPrepareLosslessFLAC, master.contains("fLaC"),
                master.contains("CHANNELS=\"\(audio.channels ?? 0)\"")
            else { throw Failure.invalidManifest }
        }
        for name in probe.isHDR ? ["video.m3u8"] : ["video.m3u8", "audio.m3u8"] {
            let playlist = try String(contentsOf: output.appendingPathComponent(name), encoding: .utf8)
            guard playlist.contains("#EXT-X-ENDLIST"), playlist.contains("#EXT-X-PLAYLIST-TYPE:VOD") else {
                throw Failure.unfinishedPlaylist
            }
        }
        let report: [String: Any] = [
            "codec": audio.codec, "precision": audio.bitsPerSample ?? 0,
            "sample_rate": audio.sampleRate ?? 0, "channels": audio.channels ?? 0,
            "layout": audio.channelLayout ?? "", "duration": result.duration,
            "source_duration": probe.duration, "subtitles": result.subtitle != nil,
            "hdr": probe.isHDR,
            "receiver_tested": false,
            "used_cache": result.usedCache,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }

    private enum Failure: Error {
        case invalidArguments, noAudio, invalidDuration, invalidManifest, unfinishedPlaylist
    }
}
