import Foundation

@main
struct PGSSubtitleHLSSmokeTest {
    static func main() async throws {
        let inputPath =
            CommandLine.arguments.dropFirst().first
            ?? ProcessInfo.processInfo.environment["AIRCILLER_TEST_PGS_MEDIA"]
        guard let inputPath, FileManager.default.fileExists(atPath: inputPath) else {
            throw NSError(
                domain: "PGSSubtitleHLSSmokeTest.Input",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Provide a file containing PGS as an argument "
                        + "or through AIRCILLER_TEST_PGS_MEDIA."
                ]
            )
        }
        let input = URL(fileURLWithPath: inputPath)
        let probe = try await MediaProbeService.probe(url: input)
        guard let track = probe.subtitleTracks.first(where: \.usesBitmapOCR) else {
            throw NSError(domain: "PGSSubtitleHLSSmokeTest.Track", code: 2)
        }
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-PGS-HLS-Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: output) }

        let playlist = """
            #EXTM3U
            #EXT-X-VERSION:7
            #EXT-X-TARGETDURATION:\(Int(ceil(probe.duration)))
            #EXT-X-MEDIA-SEQUENCE:0
            #EXT-X-PLAYLIST-TYPE:VOD
            #EXT-X-INDEPENDENT-SEGMENTS
            #EXT-X-MAP:URI="video-init.mp4"
            #EXTINF:\(String(format: "%.6f", probe.duration)),
            video-00000000.m4s
            #EXT-X-ENDLIST
            """
        try (playlist + "\n").write(
            to: output.appendingPathComponent("video.m3u8"),
            atomically: true,
            encoding: .utf8
        )
        try await SubtitleService.prepare(
            track: track,
            videoURL: input,
            delay: 0,
            videoPlaylistURL: output.appendingPathComponent("video.m3u8"),
            outputDirectory: output,
            maximumOCRFrames: 8
        )

        let subtitlePlaylist = try String(
            contentsOf: output.appendingPathComponent("subtitles.m3u8"),
            encoding: .utf8
        )
        let webVTT = try String(
            contentsOf: output.appendingPathComponent("subtitles-00000000.vtt"),
            encoding: .utf8
        )
        guard subtitlePlaylist.contains("#EXT-X-PLAYLIST-TYPE:VOD"),
            subtitlePlaylist.contains("#EXT-X-ENDLIST"),
            webVTT.contains("X-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:0"),
            webVTT.contains(" --> "),
            webVTT.contains("line:")
        else {
            throw NSError(
                domain: "PGSSubtitleHLSSmokeTest.Output",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: webVTT]
            )
        }
        print("Real PGS · local OCR · segmented and positioned HLS WebVTT · OK")
    }
}
