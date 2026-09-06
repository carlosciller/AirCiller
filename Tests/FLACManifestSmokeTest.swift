import Foundation

@main
struct FLACManifestSmokeTest {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let playlist = "#EXTM3U\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:6,\nsegment.m4s\n#EXT-X-ENDLIST\n"
        for name in ["video.m3u8", "audio.m3u8"] {
            try playlist.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        for name in ["init.mp4", "segment.m4s"] {
            try Data(repeating: 0, count: 1000).write(to: directory.appendingPathComponent(name))
        }
        let probe = MediaProbe(
            duration: 6, fileSize: nil, bitRate: 1_000_000, videoStreamIndex: 0, videoCodec: "h264",
            videoProfile: "High", videoLevel: 31, hevcCodecIdentifier: nil, width: 1280, height: 720,
            frameRate: "24/1", colorTransfer: nil, isDolbyVision: false, dolbyVisionProfile: nil,
            dolbyVisionLevel: nil, dolbyVisionCompatibilityID: nil, audioTracks: [], subtitleTracks: [], chapters: [])
        let subtitle = SubtitleTrack(
            streamIndex: 2, codec: "webvtt", language: "eng", title: nil, isDefault: true,
            isForced: false, isHearingImpaired: false, externalPath: nil)
        for channels in [1, 2, 6, 8] {
            let audio = AudioTrack(
                streamIndex: 1, codec: "FLAC", profile: nil, channels: channels, channelLayout: nil,
                language: "eng", title: nil, isDefault: true)
            for mode in AudioOutputMode.allCases {
                for selectedSubtitle in [nil, subtitle] {
                    try SubtitleService.writeMasterPlaylist(
                        probe: probe, audio: audio, audioOutputMode: mode,
                        subtitle: selectedSubtitle, outputDirectory: directory)
                    let master = try String(
                        contentsOf: directory.appendingPathComponent("master.m3u8"), encoding: .utf8)
                    guard master.contains("fLaC") == (mode == .original),
                        master.contains("wvtt") == (selectedSubtitle != nil),
                        mode != .original || master.contains("CHANNELS=\"\(channels)\"")
                    else { throw Failure.invalidManifest }
                }
            }
        }
        print("Original FLAC codec identifier, channel count, subtitles and explicit conversions: OK")
    }

    private enum Failure: Error { case invalidManifest }
}
