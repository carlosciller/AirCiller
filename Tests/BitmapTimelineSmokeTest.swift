import Foundation

@main
struct BitmapTimelineSmokeTest {
    static func main() async throws {
        for origin in ["3601.400", "1.4", "0", "-0.5"] {
            let data = Data(
                "{\"format\":{\"format_name\":\"mpegts\"},\"streams\":[{\"start_time\":\"\(origin)\"}]}".utf8)
            let actual = try PGSSubtitleConverter.transportTimeOrigin(from: data)
            guard actual == Double(origin) else { throw Failure.timeline }
        }
        for stream in [
            "[]", "[{}]", "[{\"start_time\":\"N/A\"}]", "[{\"start_time\":\"nan\"}]", "[{\"start_time\":\"inf\"}]",
        ] {
            let data = Data("{\"format\":{\"format_name\":\"mpegts\"},\"streams\":\(stream)}".utf8)
            do {
                _ = try PGSSubtitleConverter.transportTimeOrigin(from: data)
                throw Failure.acceptedUnknownOrigin
            } catch is AirCillerError {}
        }
        let matroska = Data(
            "{\"format\":{\"format_name\":\"matroska,webm\"},\"streams\":[{\"start_time\":\"4\"}]}".utf8)
        guard try PGSSubtitleConverter.transportTimeOrigin(from: matroska) == nil else { throw Failure.timeline }
        print("Bitmap subtitle clock: finite video origin required for TS; other containers unchanged: OK")
        try verifyLanguageMetadata()

        // Optional real-media regression: first cue start/end are independent
        // expectations from the source packet clock, not generated WebVTT.
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.isEmpty { return }
        guard arguments.count == 3 else { throw Failure.timeline }
        let input = URL(fileURLWithPath: arguments[0])
        guard let expectedStart = Double(arguments[1]), let expectedEnd = Double(arguments[2]) else {
            throw Failure.timeline
        }
        let probe = try await MediaProbeService.probe(url: input)
        guard let track = probe.subtitleTracks.first(where: \.usesBitmapOCR) else { throw Failure.timeline }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("AirCiller-BitmapClock-\(UUID())")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: output) }
        let direct = try await SubtitleService.materializeDirectTrack(
            track, videoURL: input, videoDuration: probe.duration, outputDirectory: output, maximumOCRFrames: 8)
        guard let path = direct.externalPath else { throw Failure.timeline }
        try verifyCue(String(contentsOfFile: path, encoding: .utf8), start: expectedStart, end: expectedEnd)
        let playlist = output.appendingPathComponent("video.m3u8")
        try "#EXTM3U\n#EXT-X-TARGETDURATION:120\n#EXTINF:120,\nvideo.m4s\n#EXT-X-ENDLIST\n".write(
            to: playlist, atomically: true, encoding: .utf8)
        try await SubtitleService.prepare(
            track: track, videoURL: input, delay: 0, videoPlaylistURL: playlist, outputDirectory: output,
            maximumOCRFrames: 8)
        let hls = try String(contentsOf: output.appendingPathComponent("subtitles-00000000.vtt"), encoding: .utf8)
        try verifyCue(hls, start: expectedStart, end: expectedEnd)
        print("Real bitmap timing: direct and HLS materialization match source cue within 2 ms: OK")
    }

    private static func verifyLanguageMetadata() throws {
        func track(_ language: String?, codec: String = "hdmv_pgs_subtitle") -> SubtitleTrack {
            SubtitleTrack(
                streamIndex: 2, codec: codec, language: language, title: "Original title",
                isDefault: false, isForced: true, isHearingImpaired: true, externalPath: nil)
        }
        let english =
            "WEBVTT\n\n00:00:01.000 --> 00:00:08.000\nThe train is leaving the station. Please take your belongings and wait behind the yellow line.\n"
        let resolved = SubtitleService.resolvedBitmapTrack(track(nil), webVTT: english)
        guard resolved.language == "eng", resolved.id == track(nil).id, resolved.isForced,
            resolved.isHearingImpaired, resolved.title?.contains("Original title") == true,
            SubtitleService.resolvedBitmapTrack(track("spa"), webVTT: english).language == "spa",
            SubtitleService.resolvedBitmapTrack(track(nil, codec: "subrip"), webVTT: english).language == nil,
            SubtitleService.resolvedBitmapTrack(track(nil), webVTT: "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHi\n")
                .language == nil,
            SubtitleService.resolvedBitmapTrack(
                track(nil),
                webVTT: "WEBVTT\n\nNOTE " + String(repeating: "The train is leaving the station. ", count: 4)
            ).language == nil
        else { throw Failure.timeline }
        print(
            "Local bitmap-language metadata: confident text only; declared languages and track identity preserved: OK")
    }

    private static func verifyCue(_ text: String, start: Double, end: Double) throws {
        guard let line = text.components(separatedBy: .newlines).first(where: { $0.contains(" --> ") }) else {
            throw Failure.timeline
        }
        let pieces = line.components(separatedBy: " --> ")
        func seconds(_ value: String) -> Double {
            let fields = value.split(separator: " ")[0].split(separator: ":").compactMap { Double($0) }
            return fields.count == 3 ? fields[0] * 3600 + fields[1] * 60 + fields[2] : -.infinity
        }
        guard abs(seconds(pieces[0]) - start) < 0.002, abs(seconds(pieces[1]) - end) < 0.002 else {
            print("Expected \(start) --> \(end), got \(line)")
            throw Failure.timeline
        }
    }

    private enum Failure: Error { case timeline, acceptedUnknownOrigin }
}
