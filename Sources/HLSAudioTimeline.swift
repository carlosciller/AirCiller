import Foundation

/// An adjusted SDR package keeps copied media on one timestamp axis. Only its
/// outer fragments are inspected; ordinary zero-adjustment playback is untouched.
enum HLSAudioTimeline {
    private struct Bounds: Sendable {
        let start: Double
        let end: Double
    }
    private struct Response: Decodable {
        struct Packet: Decodable {
            let ptsTime: String
            let durationTime: String

            private enum CodingKeys: String, CodingKey {
                case ptsTime = "pts_time"
                case durationTime = "duration_time"
            }
        }
        let packets: [Packet]
    }

    static func prepare(
        directory: URL, sourceDuration: Double, audioDelay: Double, ffprobeURL: URL
    ) async throws -> HLSAudioTimelineInfo {
        guard audioDelay.isFinite, abs(audioDelay) >= 0.001, abs(audioDelay) <= 5,
            sourceDuration.isFinite, sourceDuration > 0
        else { throw invalid() }
        var video = try SubtitleService.parseVODPlaylist(at: directory.appendingPathComponent("video.m3u8"))
        var audio = try SubtitleService.parseVODPlaylist(at: directory.appendingPathComponent("audio.m3u8"))
        guard let firstVideo = video.first, let lastVideo = video.last,
            let firstAudio = audio.first, let lastAudio = audio.last,
            !video.contains(where: \.isGap), !audio.contains(where: \.isGap)
        else { throw invalid() }
        let videoFirst = try await bounds(firstVideo, kind: "video", directory: directory, ffprobeURL: ffprobeURL)
        let videoLast =
            video.count == 1
            ? videoFirst
            : try await bounds(lastVideo, kind: "video", directory: directory, ffprobeURL: ffprobeURL)
        let audioFirst = try await bounds(firstAudio, kind: "audio", directory: directory, ffprobeURL: ffprobeURL)
        let audioLast =
            audio.count == 1
            ? audioFirst
            : try await bounds(lastAudio, kind: "audio", directory: directory, ffprobeURL: ffprobeURL)
        let origin = min(videoFirst.start, audioFirst.start)
        let end = max(videoLast.end, audioLast.end)
        let info = HLSAudioTimelineInfo(
            version: 1, sourceDuration: sourceDuration, presentationDuration: end - origin,
            timestampOrigin: origin,
            videoContentOffset: videoFirst.start + max(0, -audioDelay) - origin)
        try info.validate()
        video = try intervals(video, first: videoFirst, last: videoLast, origin: origin, end: end, kind: "video")
        audio = try intervals(audio, first: audioFirst, last: audioLast, origin: origin, end: end, kind: "audio")
        let target = Int(ceil((video + audio).map(\.duration).max() ?? 0))
        try Task.checkCancellation()
        try write(video, kind: "video", target: target, directory: directory)
        try write(audio, kind: "audio", target: target, directory: directory)
        try JSONEncoder().encode(info).write(
            to: directory.appendingPathComponent(HLSAudioTimelineInfo.fileName), options: .atomic)
        return info
    }

    private static func bounds(
        _ segment: HLSSegment, kind: String, directory: URL, ffprobeURL: URL
    ) async throws -> Bounds {
        try Task.checkCancellation()
        let initialization = directory.appendingPathComponent("\(kind)-init.mp4")
        let media = directory.appendingPathComponent(segment.fileName)
        guard !initialization.path.contains("|"), !media.path.contains("|"),
            segment.fileName == media.lastPathComponent,
            segment.fileName.hasPrefix(kind + "-"), segment.fileName.hasSuffix(".m4s")
        else { throw invalid() }
        let arguments = [
            "-v", "error", "-protocol_whitelist", "file,concat", "-show_packets",
            "-show_entries", "packet=pts_time,duration_time", "-of", "json",
            "concat:\(initialization.path)|\(media.path)",
        ]
        let data = try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask {
                let result = try await CapturedProcess.run(
                    executable: ffprobeURL, arguments: arguments, maximumOutputBytes: 1_048_576)
                guard result.status == 0 else { throw invalid() }
                return result.output
            }
            group.addTask {
                try await Task.sleep(for: .seconds(15))
                throw invalid()
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw invalid() }
            return result
        }
        let packets = try JSONDecoder().decode(Response.self, from: data).packets
        guard !packets.isEmpty, packets.count <= 20_000 else { throw invalid() }
        var start = Double.infinity
        var end = -Double.infinity
        for packet in packets {
            guard let pts = Double(packet.ptsTime), let duration = Double(packet.durationTime),
                pts.isFinite, duration.isFinite, duration > 0, (pts + duration).isFinite
            else { throw invalid() }
            start = min(start, pts)
            end = max(end, pts + duration)
        }
        guard start >= 0, end > start else { throw invalid() }
        return Bounds(start: start, end: end)
    }

    private static func intervals(
        _ original: [HLSSegment], first: Bounds, last: Bounds, origin: Double, end: Double, kind: String
    ) throws -> [HLSSegment] {
        var media = original
        media[0] = HLSSegment(index: 0, duration: first.end - first.start, startTime: 0, fileName: media[0].fileName)
        let span = last.end - first.start
        let lastDuration = span - media.dropLast().reduce(0) { $0 + $1.duration }
        guard lastDuration > 0, abs(lastDuration - (last.end - last.start)) <= 0.02 else { throw invalid() }
        media[media.count - 1] = HLSSegment(
            index: media.count - 1, duration: lastDuration, startTime: 0, fileName: media.last!.fileName)
        var result: [HLSSegment] = []
        var cursor = 0.0
        func append(duration: Double, file: String, gap: Bool = false) {
            result.append(
                HLSSegment(
                    index: result.count, duration: duration,
                    startTime: cursor, fileName: file, isGap: gap))
            cursor += duration
        }
        if first.start > origin {
            append(duration: first.start - origin, file: kind + "-leading-gap.m4s", gap: true)
        }
        for segment in media { append(duration: segment.duration, file: segment.fileName) }
        if end > last.end { append(duration: end - last.end, file: kind + "-trailing-gap.m4s", gap: true) }
        guard abs(result.reduce(0, { $0 + $1.duration }) - (end - origin)) < 0.000_5 else { throw invalid() }
        return result
    }

    private static func write(_ segments: [HLSSegment], kind: String, target: Int, directory: URL) throws {
        var lines = [
            "#EXTM3U", "#EXT-X-VERSION:8", "#EXT-X-TARGETDURATION:\(target)",
            "#EXT-X-MEDIA-SEQUENCE:0", "#EXT-X-PLAYLIST-TYPE:VOD",
        ]
        if kind == "video" { lines.append("#EXT-X-INDEPENDENT-SEGMENTS") }
        lines += ["#EXT-X-MAP:URI=\"\(kind)-init.mp4\"", "#EXT-X-PROGRAM-DATE-TIME:2000-01-01T00:00:00.000Z"]
        for segment in segments {
            if segment.isGap { lines.append("#EXT-X-GAP") }
            lines += [
                "#EXTINF:\(String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), segment.duration)),",
                segment.fileName,
            ]
        }
        lines.append("#EXT-X-ENDLIST")
        try (lines.joined(separator: "\n") + "\n").write(
            to: directory.appendingPathComponent(kind + ".m3u8"), atomically: true, encoding: .utf8)
    }

    private static func invalid() -> AirCillerError {
        .invalidVODPackage(L10n.text("No se pudo preparar la sincronización de audio sin recortar la película."))
    }
}
