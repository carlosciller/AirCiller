import Foundation

/// Opt-in real-service timing preparation. Inputs are synthetic and never sent to a receiver.
@main
struct HLSAudioTimingMediaTest {
    static func main() async throws {
        guard [6, 7, 8].contains(CommandLine.arguments.count),
            let delay = Double(CommandLine.arguments[4]), delay.isFinite, abs(delay) <= 5,
            let mode = AudioOutputMode(rawValue: CommandLine.arguments[5])
        else { throw Failure.invalidArguments }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let engine = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw Failure.invalidArguments }
        let probe = try await MediaProbeService.probe(url: source, ffprobeURL: engine.appendingPathComponent("ffprobe"))
        guard !probe.isHDR, (45...180).contains(probe.duration), let audio = probe.audioTracks.first else {
            throw Failure.unsupportedFixture
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let subtitleURL = directory.appendingPathComponent("timing.eng.srt")
        try
            "1\n00:00:00,500 --> 00:00:07,500\nAudio timing opening\n\n2\n00:00:57,500 --> 00:00:59,900\nAudio timing tail\n"
            .write(
                to: subtitleURL, atomically: true, encoding: .utf8)
        let subtitle = SubtitleTrack(
            streamIndex: nil, codec: "srt", language: "eng", title: "Timing", isDefault: true,
            isForced: false, isHearingImpaired: false, externalPath: subtitleURL.path)
        let noSubtitles = CommandLine.arguments.last == "--no-subtitles"
        let cache =
            CommandLine.arguments.count >= 7 && CommandLine.arguments[6] != "--no-subtitles"
            ? PreparedMediaCache(
                rootDirectory: URL(fileURLWithPath: CommandLine.arguments[6]), limitBytes: 1_000_000_000)
            : nil
        let result = try await HLSPreparationService.prepare(
            input: source, probe: probe, audio: audio, outputMode: mode, audioDelay: delay,
            subtitle: noSubtitles ? nil : subtitle, subtitleDelay: 0, outputDirectory: directory,
            ffmpegURL: engine.appendingPathComponent("ffmpeg"), cache: cache)
        let timeline = try HLSAudioTimelineInfo.load(directory: directory)
        let report: [String: Any] = [
            "duration": result.duration, "source_duration": probe.duration, "used_cache": result.usedCache,
            "timestamp_origin": timeline?.timestampOrigin ?? 0,
            "video_content_offset": timeline?.videoContentOffset ?? 0,
        ]
        FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: report, options: .sortedKeys))
    }

    private enum Failure: Error { case invalidArguments, unsupportedFixture }
}
