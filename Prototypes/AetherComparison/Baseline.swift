import Foundation

@main
struct AirCillerComparisonBaseline {
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 5 else { exit(2) }
        let input = URL(fileURLWithPath: args[1])
        let directory = URL(fileURLWithPath: args[2])
        let ffmpeg = URL(fileURLWithPath: args[3])
        let ffprobe = URL(fileURLWithPath: args[4])
        let began = ProcessInfo.processInfo.systemUptime
        let probe = try await MediaProbeService.probe(url: input, ffprobeURL: ffprobe)
        let result = try await HLSPreparationService.prepare(
            input: input, probe: probe, audio: probe.audioTracks.first, outputMode: .original,
            audioDelay: 0, subtitle: probe.subtitleTracks.first, subtitleDelay: 0,
            outputDirectory: directory, ffmpegURL: ffmpeg)
        let report: [String: Any] = [
            "seconds": ProcessInfo.processInfo.systemUptime - began,
            "duration": result.duration, "usedCache": result.usedCache,
            "route": "HLSPreparationService", "originalAudio": true
        ]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("baseline.json"))
    }
}
