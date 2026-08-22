import Foundation

@main
struct PrepareExistingVOD {
    static func main() async throws {
        guard CommandLine.arguments.count == 5,
            let audioIndex = Int(CommandLine.arguments[3])
        else {
            throw NSError(domain: "PrepareExistingVOD.Usage", code: 2)
        }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let subtitleArgument = CommandLine.arguments[4]
        let probe = try await MediaProbeService.probe(url: input)
        guard let audio = probe.audioTracks.first(where: { $0.streamIndex == audioIndex }) else {
            throw NSError(domain: "PrepareExistingVOD.Audio", code: 3)
        }

        try SubtitleService.alignRenditionPlaylists(
            outputDirectory: output,
            expectedDuration: min(probe.duration, 60)
        )
        let subtitle: SubtitleTrack?
        if subtitleArgument == "none" {
            subtitle = nil
        } else if let subtitleIndex = Int(subtitleArgument) {
            guard let selected = probe.subtitleTracks.first(where: { $0.streamIndex == subtitleIndex }) else {
                throw NSError(domain: "PrepareExistingVOD.Subtitle", code: 4)
            }
            subtitle = selected
            try await SubtitleService.prepare(
                track: selected,
                videoURL: input,
                delay: 0,
                videoPlaylistURL: output.appendingPathComponent("video.m3u8"),
                outputDirectory: output
            )
            try SubtitleService.alignRenditionPlaylists(
                outputDirectory: output,
                expectedDuration: min(probe.duration, 60)
            )
        } else {
            throw NSError(domain: "PrepareExistingVOD.SubtitleArgument", code: 5)
        }

        try SubtitleService.writeMasterPlaylist(
            probe: probe,
            audio: audio,
            audioOutputMode: .original,
            subtitle: subtitle,
            outputDirectory: output
        )
        let duration = try SubtitleService.validatePackage(
            outputDirectory: output,
            expectedDuration: min(probe.duration, 60),
            hasAudio: true,
            hasSubtitles: subtitle != nil
        )
        print("VOD preparado: \(TimeFormatting.duration(duration))")
    }
}
