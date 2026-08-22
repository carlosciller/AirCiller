import Foundation

@main
struct SubtitleSmokeTest {
    static func main() async throws {
        guard CommandLine.arguments.count == 4,
            let streamIndex = Int(CommandLine.arguments[2])
        else {
            throw NSError(domain: "SubtitleSmokeTest", code: 2)
        }
        let videoURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        let detected = try await MediaProbeService.probe(url: videoURL)
        guard detected.subtitleTracks.contains(where: { $0.streamIndex == streamIndex }) else {
            throw NSError(domain: "SubtitleSmokeTest", code: 3)
        }

        let track = SubtitleTrack(
            streamIndex: streamIndex,
            codec: "subrip",
            language: "spa",
            title: "Español de prueba",
            isDefault: false,
            isForced: false,
            isHearingImpaired: false,
            externalPath: nil
        )
        let videoPlaylist = """
            #EXTM3U
            #EXT-X-VERSION:7
            #EXT-X-TARGETDURATION:180
            #EXT-X-MEDIA-SEQUENCE:0
            #EXT-X-PLAYLIST-TYPE:VOD
            #EXT-X-INDEPENDENT-SEGMENTS
            #EXT-X-MAP:URI="video-init.mp4"
            #EXTINF:180.000000,
            video-00000000.m4s
            #EXTINF:180.000000,
            video-00000001.m4s
            #EXT-X-ENDLIST
            """
        try (videoPlaylist + "\n").write(
            to: outputURL.appendingPathComponent("video.m3u8"),
            atomically: true,
            encoding: .utf8
        )
        for name in ["video-init.mp4", "video-00000000.m4s", "video-00000001.m4s"] {
            try Data([0]).write(to: outputURL.appendingPathComponent(name))
        }
        try await SubtitleService.prepare(
            track: track,
            videoURL: videoURL,
            delay: 0.4,
            videoPlaylistURL: outputURL.appendingPathComponent("video.m3u8"),
            outputDirectory: outputURL
        )
        let baselineURL = outputURL.appendingPathComponent("baseline", isDirectory: true)
        try FileManager.default.createDirectory(at: baselineURL, withIntermediateDirectories: true)
        try await SubtitleService.prepare(
            track: track,
            videoURL: videoURL,
            delay: 0,
            videoPlaylistURL: outputURL.appendingPathComponent("video.m3u8"),
            outputDirectory: baselineURL
        )
        let probe = MediaProbe(
            duration: 360,
            fileSize: nil,
            bitRate: 24_000_000,
            videoStreamIndex: 0,
            videoCodec: "hevc",
            videoProfile: "Main 10",
            videoLevel: 150,
            hevcCodecIdentifier: "hvc1.2.20000000.H150.B0",
            width: 3840,
            height: 1608,
            frameRate: "24/1",
            colorTransfer: "smpte2084",
            isDolbyVision: true,
            dolbyVisionProfile: 8,
            dolbyVisionLevel: 6,
            dolbyVisionCompatibilityID: 1,
            audioTracks: [],
            subtitleTracks: [track],
            chapters: []
        )
        try SubtitleService.writeMasterPlaylist(
            probe: probe,
            audio: nil,
            audioOutputMode: .original,
            subtitle: track,
            outputDirectory: outputURL
        )
        let master = try String(
            contentsOf: outputURL.appendingPathComponent("master.m3u8"),
            encoding: .utf8
        )
        guard master.contains("#EXT-X-VERSION:7"),
            master.contains("SUPPLEMENTAL-CODECS=\"dvh1.08.06/db1p\""),
            master.contains("VIDEO-RANGE=PQ"),
            master.contains("CODECS=\"hvc1.2.20000000.H150.B0,wvtt\""),
            master.contains("SUBTITLES=\"subs\""),
            !master.contains("TYPE=AUDIO"),
            !master.contains("AUDIO=\"audio\""),
            !master.contains("#EXT-X-I-FRAME-STREAM-INF:")
        else {
            throw NSError(domain: "SubtitleSmokeTest.DolbyVisionManifest", code: 6)
        }
        let duration = try SubtitleService.validatePackage(
            outputDirectory: outputURL,
            expectedDuration: 360,
            hasAudio: false,
            hasSubtitles: true
        )
        guard abs(duration - 360) < 0.001 else {
            throw NSError(domain: "SubtitleSmokeTest", code: 4)
        }
        let firstSegment = try String(
            contentsOf: outputURL.appendingPathComponent("subtitles-00000000.vtt"),
            encoding: .utf8
        )
        let baselineSegment = try String(
            contentsOf: baselineURL.appendingPathComponent("subtitles-00000000.vtt"),
            encoding: .utf8
        )
        guard let delayedStart = firstCueStart(in: firstSegment),
            let baselineStart = firstCueStart(in: baselineSegment),
            abs((delayedStart - baselineStart) - 0.4) < 0.002
        else {
            throw NSError(domain: "SubtitleSmokeTest.Delay", code: 5)
        }
        print(outputURL.path)
    }

    private static func firstCueStart(in text: String) -> Double? {
        guard let line = text.split(separator: "\n").first(where: { $0.contains(" --> ") }),
            let value = line.split(separator: " ").first
        else { return nil }
        let fields = value.split(separator: ":")
        guard fields.count == 3,
            let hours = Double(fields[0]),
            let minutes = Double(fields[1]),
            let seconds = Double(fields[2])
        else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}
