import Foundation

@main
struct HLSSubtitlePreparationSmokeTest {
    static func main() async throws {
        guard let path = ProcessInfo.processInfo.environment["AIRCILLER_TEST_FFMPEG"],
            FileManager.default.isExecutableFile(atPath: path)
        else { throw Failure.missingPinnedEngine }
        let ffmpeg = URL(fileURLWithPath: path)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-HLS-Subtitle-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        try await verifyTextPreparation(root: root, ffmpeg: ffmpeg)
        try verifyBitmapDuration(root: root)
        try verifyIncompletePlaylist(root: root)
        try await verifyCancellation(root: root)
        try await verifyFailureCleanup(root: root)
        print(
            "HLS subtitle staging: text/ASS timing, exact VOD boundaries, bitmap duration, cancellation and cleanup: OK"
        )
    }

    private static func verifyTextPreparation(root: URL, ffmpeg: URL) async throws {
        let directory = try makeDirectory(root, "text")
        let source = directory.appendingPathComponent("captions.srt")
        try """
        1
        00:00:01,000 --> 00:00:07,000
        Across the segment boundary

        2
        00:00:10,000 --> 00:00:11,000
        Second caption

        """.write(to: source, atomically: true, encoding: .utf8)
        let track = makeTrack(codec: "subrip", source: source)
        let content = try await SubtitleService.materializeHLSContent(
            track: track, videoURL: root.appendingPathComponent("not-yet-prepared.mkv"),
            videoDuration: 99, outputDirectory: directory, ffmpegURL: ffmpeg)
        guard content.track == track, content.bitmapDuration == nil,
            !FileManager.default.fileExists(atPath: directory.appendingPathComponent("subtitles.m3u8").path),
            try rawFiles(in: directory).isEmpty
        else { throw Failure.prematureOutput }

        let playlist = try makePlaylist(directory)
        let resolved = try SubtitleService.finalizeHLSContent(
            content, delay: 0.5, videoPlaylistURL: playlist, outputDirectory: directory)
        let header = "WEBVTT\nX-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:0"
        let firstCue = "00:00:01.500 --> 00:00:07.500\nAcross the segment boundary"
        let secondCue = "00:00:10.500 --> 00:00:11.500\nSecond caption"
        guard resolved == track,
            try read(directory, "subtitles-00000000.vtt") == header + "\n\n" + firstCue + "\n",
            try read(directory, "subtitles-00000001.vtt") == header + "\n\n" + firstCue + "\n\n" + secondCue + "\n\n"
        else {
            throw Failure.textGoldenOutput(
                "first=\(try read(directory, "subtitles-00000000.vtt").debugDescription); "
                    + "second=\(try read(directory, "subtitles-00000001.vtt").debugDescription)")
        }
        let subtitleSegments = try SubtitleService.parseVODPlaylist(
            at: directory.appendingPathComponent("subtitles.m3u8"))
        guard subtitleSegments.map(\.duration) == [6, 6],
            try read(directory, "subtitles.m3u8").contains("#EXT-X-ENDLIST")
        else { throw Failure.segmentTimeline }

        let shifted = try makeDirectory(root, "shifted")
        try SubtitleService.finalizeHLSContent(content, delay: -2, videoPlaylistURL: playlist, outputDirectory: shifted)
        guard try read(shifted, "subtitles-00000000.vtt").contains("00:00:00.000 --> 00:00:05.000") else {
            throw Failure.negativeDelayOutput
        }

        let ass = directory.appendingPathComponent("captions.ass")
        try """
        [Script Info]
        ScriptType: v4.00+
        PlayResX: 1920
        PlayResY: 1080
        [V4+ Styles]
        Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
        Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,0,8,20,20,20,1
        [Events]
        Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
        Dialogue: 0,0:00:02.00,0:00:08.00,Default,,0,0,0,,{\\i1}Styled caption{\\i0}
        """.write(to: ass, atomically: true, encoding: .utf8)
        let styled = try await SubtitleService.materializeHLSContent(
            track: makeTrack(codec: "ass", source: ass), videoURL: source,
            videoDuration: 99, outputDirectory: directory, ffmpegURL: ffmpeg)
        guard styled.webVTT.contains("<i>Styled caption</i>"), styled.webVTT.contains("line:") else {
            throw Failure.assMaterializationOutput
        }
        let styledOutput = try makeDirectory(root, "styled")
        try SubtitleService.finalizeHLSContent(
            styled, delay: 0, videoPlaylistURL: playlist, outputDirectory: styledOutput)
        for index in 0..<2 {
            let value = try read(styledOutput, String(format: "subtitles-%08d.vtt", index))
            guard value.contains("00:00:02.000 --> 00:00:08.000"), value.contains("<i>Styled caption</i>") else {
                throw Failure.assSegmentOutput
            }
        }
        guard try rawFiles(in: directory).isEmpty else { throw Failure.retainedTemporaryFile }
    }

    private static func verifyBitmapDuration(root: URL) throws {
        let directory = try makeDirectory(root, "bitmap")
        let playlist = try makePlaylist(directory)
        let content = HLSSubtitleContent(
            track: makeTrack(codec: "hdmv_pgs_subtitle", source: root.appendingPathComponent("captions.sup")),
            webVTT: "WEBVTT\n\n00:00:01.000 --> 00:00:13.000\nLast open bitmap\n", bitmapDuration: 13)
        do {
            try SubtitleService.finalizeHLSContent(
                content, delay: 0, videoPlaylistURL: playlist, outputDirectory: directory)
            throw Failure.acceptedEstimatedBitmapDuration
        } catch AirCillerError.invalidVODPackage {}
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("subtitles.m3u8").path) else {
            throw Failure.prematureOutput
        }
    }

    private static func verifyCancellation(root: URL) async throws {
        let directory = try makeDirectory(root, "cancel")
        let helper = root.appendingPathComponent("slow-extractor")
        try """
        #!/bin/sh
        for argument in "$@"; do output="$argument"; done
        printf 'partial subtitle' > "$output"
        exec /bin/sleep 30
        """.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        let task = Task {
            try await SubtitleService.materializeHLSContent(
                track: makeTrack(codec: "subrip", source: directory.appendingPathComponent("source.srt")),
                videoURL: directory.appendingPathComponent("movie.mkv"), videoDuration: 12,
                outputDirectory: directory, ffmpegURL: helper)
        }
        defer { task.cancel() }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while try rawFiles(in: directory).isEmpty {
            guard ContinuousClock.now < deadline else { throw Failure.extractionDidNotStart }
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        do {
            _ = try await task.value
            throw Failure.ignoredCancellation
        } catch is CancellationError {}
        guard try rawFiles(in: directory).isEmpty else { throw Failure.retainedTemporaryFile }

        let gate = Gate()
        let cancelledBeforeStart = Task {
            await gate.wait()
            return try await SubtitleService.materializeHLSContent(
                track: makeTrack(codec: "subrip", source: helper), videoURL: helper, videoDuration: 12,
                outputDirectory: directory, ffmpegURL: helper)
        }
        cancelledBeforeStart.cancel()
        await gate.open()
        do {
            _ = try await cancelledBeforeStart.value
            throw Failure.ignoredCancellation
        } catch is CancellationError {}
        guard try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty else {
            throw Failure.prematureOutput
        }
    }

    private static func verifyIncompletePlaylist(root: URL) throws {
        let directory = try makeDirectory(root, "incomplete")
        let playlist = directory.appendingPathComponent("video.m3u8")
        let content = HLSSubtitleContent(
            track: makeTrack(codec: "webvtt", source: root.appendingPathComponent("captions.vtt")),
            webVTT: "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nCaption\n", bitmapDuration: nil)
        for invalid in [
            "#EXTM3U\n#EXTINF:6,\nvideo.m4s\n",
            "#EXTM3U\n#EXTINF:nan,\nvideo.m4s\n#EXT-X-ENDLIST\n",
            "#EXTM3U\n#EXTINF:-1,\nvideo.m4s\n#EXT-X-ENDLIST\n",
        ] {
            try invalid.write(to: playlist, atomically: true, encoding: .utf8)
            do {
                try SubtitleService.finalizeHLSContent(
                    content, delay: 0, videoPlaylistURL: playlist, outputDirectory: directory)
                throw Failure.acceptedIncompletePlaylist
            } catch AirCillerError.invalidVODPackage {}
        }
        guard !FileManager.default.fileExists(atPath: directory.appendingPathComponent("subtitles.m3u8").path) else {
            throw Failure.prematureOutput
        }
    }

    private static func verifyFailureCleanup(root: URL) async throws {
        let directory = try makeDirectory(root, "failure")
        let helper = root.appendingPathComponent("failing-extractor")
        try """
        #!/bin/sh
        for argument in "$@"; do output="$argument"; done
        printf 'partial subtitle' > "$output"
        exit 1
        """.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        do {
            _ = try await SubtitleService.materializeHLSContent(
                track: makeTrack(codec: "subrip", source: helper), videoURL: helper, videoDuration: 12,
                outputDirectory: directory, ffmpegURL: helper)
            throw Failure.acceptedFailedExtraction
        } catch AirCillerError.subtitlePreparationFailed {}
        guard try rawFiles(in: directory).isEmpty else { throw Failure.retainedTemporaryFile }
    }

    private static func makeDirectory(_ root: URL, _ name: String) throws -> URL {
        let url = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private static func makePlaylist(_ directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("video.m3u8")
        try
            "#EXTM3U\n#EXT-X-TARGETDURATION:6\n#EXT-X-PLAYLIST-TYPE:VOD\n#EXTINF:6,\na.m4s\n#EXTINF:6,\nb.m4s\n#EXT-X-ENDLIST\n"
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private static func makeTrack(codec: String, source: URL) -> SubtitleTrack {
        SubtitleTrack(
            streamIndex: 0, codec: codec, language: "eng", title: "Original title", isDefault: true,
            isForced: false, isHearingImpaired: true, externalPath: source.path)
    }

    private static func read(_ directory: URL, _ name: String) throws -> String {
        try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
    }

    private static func rawFiles(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("subtitles-raw-") }
    }

    private actor Gate {
        private var isOpen = false
        private var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func open() {
            isOpen = true
            continuation?.resume()
            continuation = nil
        }
    }

    private enum Failure: Error {
        case missingPinnedEngine, prematureOutput, negativeDelayOutput, segmentTimeline
        case textGoldenOutput(String)
        case assMaterializationOutput, assSegmentOutput, acceptedEstimatedBitmapDuration
        case acceptedIncompletePlaylist
        case extractionDidNotStart, ignoredCancellation, retainedTemporaryFile, acceptedFailedExtraction
    }
}
