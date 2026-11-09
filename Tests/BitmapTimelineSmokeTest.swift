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
        try verifyTerminalBitmap()
        try verifyEmbeddedCacheDuration()
        try await verifyCachedSelection()
        try await verifyExternalPGS()
        try verifyExternalVobSub()

        // Optional real-media regression: first cue start/end are independent
        // expectations from the source packet clock, not generated WebVTT.
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.isEmpty { return }
        guard arguments.count == 3 || arguments.count == 4 else { throw Failure.timeline }
        let input = URL(fileURLWithPath: arguments[0])
        guard let expectedStart = Double(arguments[1]), let expectedEnd = Double(arguments[2]) else {
            throw Failure.timeline
        }
        let probe = try await MediaProbeService.probe(url: input)
        guard
            let track = arguments.count == 4
                ? try MediaProbeService.externalTracks(url: URL(fileURLWithPath: arguments[3])).first
                : probe.subtitleTracks.first(where: \.usesBitmapOCR)
        else { throw Failure.timeline }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("AirCiller-BitmapClock-\(UUID())")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: output) }
        let frameLimit = 8
        let direct = try await SubtitleService.materializeDirectTrack(
            track, videoURL: input, videoDuration: probe.duration, outputDirectory: output, maximumOCRFrames: frameLimit
        )
        guard let path = direct.externalPath else { throw Failure.timeline }
        try verifyCue(String(contentsOfFile: path, encoding: .utf8), start: expectedStart, end: expectedEnd)
        let playlist = output.appendingPathComponent("video.m3u8")
        try "#EXTM3U\n#EXT-X-TARGETDURATION:120\n#EXTINF:120,\nvideo.m4s\n#EXT-X-ENDLIST\n".write(
            to: playlist, atomically: true, encoding: .utf8)
        try await SubtitleService.prepare(
            track: track, videoURL: input, delay: 0, videoPlaylistURL: playlist, outputDirectory: output,
            maximumOCRFrames: frameLimit)
        let hls = try String(contentsOf: output.appendingPathComponent("subtitles-00000000.vtt"), encoding: .utf8)
        try verifyCue(hls, start: expectedStart, end: expectedEnd)
        print("Real bitmap timing: direct and HLS materialization match source cue within 2 ms: OK")
    }

    private static func verifyTerminalBitmap() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AirCiller-BitmapEnd-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        // Grouping compares encoded frames; no OCR or image decoder is needed.
        let frame = directory.appendingPathComponent("frame-0000000098000000.png")
        try Data([1]).write(to: frame)
        let bounds = [Int64(98_000_000): CGRect(x: 0, y: 0, width: 100, height: 30)]
        let groups = try PGSSubtitleConverter.frameGroups(
            in: directory, videoDuration: 100, isTruncated: false, frameBounds: bounds)
        guard groups.count == 1, groups[0].start == 98, groups[0].end == 100 else {
            throw Failure.terminalBitmap
        }
        let truncated = try PGSSubtitleConverter.frameGroups(
            in: directory, videoDuration: 100, isTruncated: true, frameBounds: bounds)
        guard truncated.count == 1, truncated[0].end == 103 else { throw Failure.terminalBitmap }
        // A later clear must not extend the visible cue beyond the movie either.
        try Data([0]).write(to: directory.appendingPathComponent("frame-0000000101000000.png"))
        let cleared = try PGSSubtitleConverter.frameGroups(
            in: directory, videoDuration: 100, isTruncated: false, frameBounds: bounds)
        guard cleared.count == 1, cleared[0].end == 100 else { throw Failure.terminalBitmap }
        let outside = try PGSSubtitleConverter.frameGroups(
            in: directory, videoDuration: 90, isTruncated: false, frameBounds: bounds)
        guard outside.isEmpty else { throw Failure.terminalBitmap }
        try Data([0]).write(to: directory.appendingPathComponent("frame-0000000099000000.png"))
        let explicitClear = try PGSSubtitleConverter.frameGroups(
            in: directory, videoDuration: 100, isTruncated: false, frameBounds: bounds)
        guard explicitClear.count == 2, explicitClear[0].end == 99, explicitClear[1].bounds == nil else {
            throw Failure.terminalBitmap
        }
        print("Bitmap completion: final open cue and late clear bounded by movie end: OK")
    }

    private static func verifyEmbeddedCacheDuration() throws {
        let movie = URL(fileURLWithPath: "/synthetic-cache-identity.mkv")
        for codec in ["hdmv_pgs_subtitle", "dvd_subtitle"] {
            let track = SubtitleTrack(
                streamIndex: 2, codec: codec, language: "eng", title: nil,
                isDefault: false, isForced: false, isHearingImpaired: false, externalPath: nil)
            let first = PGSSubtitleConverter.cacheFileName(track: track, videoURL: movie, videoDuration: 100)
            guard first != PGSSubtitleConverter.cacheFileName(track: track, videoURL: movie, videoDuration: 101),
                first == PGSSubtitleConverter.cacheFileName(track: track, videoURL: movie, videoDuration: 100)
            else { throw Failure.cacheDuration }
        }
        print("Embedded bitmap cache: exact duration distinguishes results; repeated selection retains identity: OK")
    }

    private static func verifyCachedSelection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AirCiller-BitmapCache-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let movie = directory.appendingPathComponent("movie.mkv")
        try Data([1]).write(to: movie)
        let vtt =
            "WEBVTT\n\nNOTE AirCiller Bitmap OCR v3; cues=1; confidence=0.9500\n\n"
            + "00:01:38.000 --> 00:01:40.000\nFinal caption\n"
        for codec in ["hdmv_pgs_subtitle", "dvd_subtitle"] {
            let track = SubtitleTrack(
                streamIndex: 2, codec: codec, language: "eng", title: nil,
                isDefault: false, isForced: false, isHearingImpaired: false, externalPath: nil)
            let cached = directory.appendingPathComponent(
                PGSSubtitleConverter.cacheFileName(track: track, videoURL: movie, videoDuration: 100))
            try vtt.write(to: cached, atomically: true, encoding: .utf8)
            // The source is intentionally not media. Any attempt to re-render
            // rather than reuse the prepared track fails this check.
            for _ in 0..<2 {
                let result = try await PGSSubtitleConverter.convert(
                    track: track, videoURL: movie, videoDuration: 100, cacheDirectory: directory)
                guard result.usedCache, result.webVTT == vtt, result.cueCount == 1 else {
                    throw Failure.cacheDuration
                }
            }
            for invalid in [0, -1, Double.infinity, Double.nan] {
                do {
                    _ = try await PGSSubtitleConverter.convert(
                        track: track, videoURL: movie, videoDuration: invalid, cacheDirectory: directory)
                    throw Failure.cacheDuration
                } catch AirCillerError.subtitlePreparationFailed {}
            }
        }
        print("Bitmap repeated selection: cached PGS/VobSub returned without decoding; invalid durations rejected: OK")
    }

    private static func verifyExternalPGS() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AirCiller-ExternalPGS-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("movie.eng.forced.SUP")
        let other = directory.appendingPathComponent("other.sup")
        let movie = directory.appendingPathComponent("movie.mkv")
        try Data([0x50, 0x47]).write(to: source)
        let track = MediaProbeService.externalTrack(url: source)
        guard track.usesBitmapOCR, track.isSelectable, track.streamIndex == 0,
            track.language == "eng", track.isForced, track.externalPath == source.path,
            MediaProbeService.externalTrack(url: source).id == track.id,
            MediaProbeService.externalTrack(url: other).id != track.id,
            MediaProbeService.externalTrack(url: directory.appendingPathComponent("captions.srt")).isTextBased
        else { throw Failure.timeline }
        func key(_ selected: SubtitleTrack = track, duration: Double = 120) -> String {
            PGSSubtitleConverter.cacheFileName(track: selected, videoURL: movie, videoDuration: duration)
        }
        let initial = key()
        guard initial != key(duration: 60), initial != key(MediaProbeService.externalTrack(url: other)) else {
            throw Failure.timeline
        }
        try Data([0x50, 0x47, 0x01]).write(to: source)
        guard initial != key() else { throw Failure.timeline }
        try Data("not a PGS subtitle".utf8).write(to: source)
        do {
            _ = try await PGSSubtitleConverter.convert(
                track: track, videoURL: movie, videoDuration: 120, cacheDirectory: directory)
            throw Failure.timeline
        } catch AirCillerError.unsupportedSubtitle {}
        try FileManager.default.removeItem(at: source)
        do {
            _ = try await PGSSubtitleConverter.convert(
                track: track, videoURL: movie, videoDuration: 120, cacheDirectory: directory)
            throw Failure.timeline
        } catch is CocoaError {}
        print("External PGS: track metadata, source/duration cache identity, malformed and missing files: OK")
    }

    private static func verifyExternalVobSub() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AirCiller-VobSub-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let idx = directory.appendingPathComponent("movie.IDX")
        let sub = directory.appendingPathComponent("movie.sub")
        let movie = directory.appendingPathComponent("movie.mkv")
        let header =
            "# VobSub index file, v7\nsize: 720x576\npalette: "
            + Array(repeating: "ffffff", count: 16).joined(separator: ", ") + "\nlangidx: 1\n"
        let entries =
            "id: fr, index: 0\nid: en, index: 7\nalt: English SDH\n"
            + "timestamp: 00:00:05:000, filepos: 000000000\n"
            + "id: es, index: 2\nalt: Castellano\ntimestamp: 00:00:10:000, filepos: 000000004\n"
        try Data([0, 0, 1, 0xBA, 0, 0, 0, 0]).write(to: sub)
        try (header + entries).write(to: idx, atomically: true, encoding: .utf8)
        let pair = try ExternalVobSub(url: sub)
        let tracks = try MediaProbeService.externalTracks(url: idx)
        guard pair.indexURL.resolvingSymlinksInPath() == idx.resolvingSymlinksInPath(),
            pair.bitmapURL.resolvingSymlinksInPath() == sub.resolvingSymlinksInPath(), tracks.count == 2,
            tracks[0].streamIndex == 0, tracks[0].language == "eng", tracks[0].originalName == "English SDH",
            tracks[1].streamIndex == 1, tracks[1].language == "spa", tracks[1].isDefault,
            tracks[0].id != tracks[1].id, tracks.allSatisfy(\.usesBitmapOCR),
            pair.tracks.map(\.id) == tracks.map(\.id),
            MediaProbeService.discoverExternalSubtitles(for: movie).map(\.id) == tracks.map(\.id)
        else { throw Failure.timeline }
        func key(_ track: SubtitleTrack = tracks[0], duration: Double = 120) -> String {
            PGSSubtitleConverter.cacheFileName(track: track, videoURL: movie, videoDuration: duration)
        }
        let first = key()
        guard first != key(tracks[1]), first != key(duration: 60) else { throw Failure.timeline }
        try Data([0, 0, 1, 0xBA, 0, 0, 0, 0, 1]).write(to: sub)
        let second = key()
        guard first != second else { throw Failure.timeline }
        try (header + entries + "# changed palette source\n").write(to: idx, atomically: true, encoding: .utf8)
        guard second != key() else { throw Failure.timeline }
        let spaced = (header + entries).replacingOccurrences(of: "id: en, index: 7", with: "id:  en,  index: 7  ")
            .replacingOccurrences(of: "timestamp: ", with: "timestamp:\t")
        try spaced.write(to: idx, atomically: true, encoding: .utf8)
        guard try ExternalVobSub(url: idx).tracks.map(\.id) == tracks.map(\.id) else { throw Failure.timeline }
        for invalid in [
            "{1}{100}MicroDVD text", header, header + "timestamp: 00:00:00:000, filepos: 0\n",
            (header + entries).replacingOccurrences(of: "index: 7", with: "index: 32"),
            (header + entries).replacingOccurrences(of: "00:00:05:000", with: "00:60:05:000"),
            (header + entries).replacingOccurrences(of: "000000004", with: "FFFFFFFFFFFFFFFF"),
            (header + entries).replacingOccurrences(of: "size: 720x576", with: "size: 99999x576"),
            (header + entries).replacingOccurrences(of: "palette:", with: "missing:"),
            String(repeating: "x", count: 4_194_305),
        ] {
            try invalid.write(to: idx, atomically: true, encoding: .utf8)
            do {
                _ = try ExternalVobSub(url: idx)
                throw Failure.timeline
            } catch AirCillerError.unsupportedSubtitle {}
        }
        try (header + entries).write(to: idx, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: sub)
        do {
            _ = try ExternalVobSub(url: idx)
            throw Failure.timeline
        } catch AirCillerError.unsupportedSubtitle {}
        guard MediaProbeService.discoverExternalSubtitles(for: movie).isEmpty else { throw Failure.timeline }
        print("External VobSub: pair resolution, sparse/empty IDs, languages, cache invalidation and damaged files: OK")
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
            FileHandle.standardError.write(Data("Expected \(start) --> \(end), got \(line)\n".utf8))
            throw Failure.timeline
        }
    }

    private enum Failure: Error { case timeline, acceptedUnknownOrigin, terminalBitmap, cacheDuration }
}
