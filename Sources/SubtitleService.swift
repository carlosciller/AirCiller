import Foundation

struct HLSSegment: Hashable, Sendable {
    let index: Int
    let duration: Double
    let startTime: Double
    let fileName: String
}

enum SubtitleService {
    static func alignRenditionPlaylists(outputDirectory: URL, expectedDuration: Double) throws {
        let videoURL = outputDirectory.appendingPathComponent("video.m3u8")
        let audioURL = outputDirectory.appendingPathComponent("audio.m3u8")
        var videoText = try String(contentsOf: videoURL, encoding: .utf8)
        videoText = normalizedVODPlaylist(videoText)
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            try videoText.write(to: videoURL, atomically: true, encoding: .utf8)
            return
        }

        var audioText = normalizedVODPlaylist(
            try String(contentsOf: audioURL, encoding: .utf8)
        )
        guard
            let targetLine =
                videoText
                .components(separatedBy: .newlines)
                .first(where: { $0.hasPrefix("#EXT-X-TARGETDURATION:") }),
            let audioTargetLine =
                audioText
                .components(separatedBy: .newlines)
                .first(where: { $0.hasPrefix("#EXT-X-TARGETDURATION:") })
        else {
            throw AirCillerError.invalidVODPackage("No se pudo alinear la duración objetivo de vídeo y audio.")
        }
        if targetLine != audioTargetLine {
            audioText = audioText.replacingOccurrences(of: audioTargetLine, with: targetLine)
        }

        let videoSegments = try parseVODPlaylistText(videoText)
        let audioSegments = try parseVODPlaylistText(audioText)
        let videoDuration = videoSegments.reduce(0) { $0 + $1.duration }
        let audioDuration = audioSegments.reduce(0) { $0 + $1.duration }
        if abs(videoDuration - audioDuration) >= 0.000_5 {
            let audioAdjustment = videoDuration - audioDuration
            let videoAdjustment = audioDuration - videoDuration
            let preferVideo = abs(videoDuration - expectedDuration) <= abs(audioDuration - expectedDuration)
            let canAdjustAudio = (audioSegments.last?.duration ?? 0) + audioAdjustment > 0
            let canAdjustVideo = (videoSegments.last?.duration ?? 0) + videoAdjustment > 0

            if (preferVideo && canAdjustAudio) || !canAdjustVideo {
                audioText = try replacingLastSegmentDuration(
                    in: audioText,
                    adjustment: audioAdjustment
                )
            } else {
                videoText = try replacingLastSegmentDuration(
                    in: videoText,
                    adjustment: videoAdjustment
                )
            }
        }

        try videoText.write(to: videoURL, atomically: true, encoding: .utf8)
        try audioText.write(
            to: audioURL,
            atomically: true,
            encoding: .utf8
        )

        let subtitleURL = outputDirectory.appendingPathComponent("subtitles.m3u8")
        if FileManager.default.fileExists(atPath: subtitleURL.path) {
            var subtitleText = normalizedVODPlaylist(
                try String(contentsOf: subtitleURL, encoding: .utf8)
            )
            if let subtitleTargetLine =
                subtitleText
                .components(separatedBy: .newlines)
                .first(where: { $0.hasPrefix("#EXT-X-TARGETDURATION:") }),
                subtitleTargetLine != targetLine
            {
                subtitleText = subtitleText.replacingOccurrences(of: subtitleTargetLine, with: targetLine)
            }
            let alignedVideoDuration = try parseVODPlaylistText(videoText).reduce(0) { $0 + $1.duration }
            let subtitleDuration = try parseVODPlaylistText(subtitleText).reduce(0) { $0 + $1.duration }
            if abs(alignedVideoDuration - subtitleDuration) >= 0.000_5 {
                subtitleText = try replacingLastSegmentDuration(
                    in: subtitleText,
                    adjustment: alignedVideoDuration - subtitleDuration
                )
            }
            try subtitleText.write(to: subtitleURL, atomically: true, encoding: .utf8)
        }
    }

    static func prepare(
        track: SubtitleTrack,
        videoURL: URL,
        delay: Double,
        videoPlaylistURL: URL,
        outputDirectory: URL,
        maximumOCRFrames: Int? = nil,
        ocrProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async throws {
        guard track.isSelectable else {
            throw AirCillerError.unsupportedSubtitle(track.unsupportedReason ?? "Pista de subtítulos no compatible.")
        }

        do {
            let segments = try parseVODPlaylist(at: videoPlaylistURL)
            guard !segments.isEmpty else {
                throw AirCillerError.invalidVODPackage("La película no contiene segmentos de vídeo.")
            }

            let webVTT: String
            if track.usesBitmapOCR {
                let conversion = try await PGSSubtitleConverter.convert(
                    track: track,
                    videoURL: videoURL,
                    videoDuration: segments.reduce(0) { $0 + $1.duration },
                    maximumRenderedFrames: maximumOCRFrames,
                    progress: ocrProgress
                )
                webVTT = conversion.webVTT
            } else {
                let rawExtension = track.usesAdvancedTextStyling ? "ass" : "vtt"
                let rawURL = outputDirectory.appendingPathComponent("subtitles-raw.\(rawExtension)")
                try await extractWebVTT(track: track, videoURL: videoURL, outputURL: rawURL)
                defer { try? FileManager.default.removeItem(at: rawURL) }

                let raw = (try? String(contentsOf: rawURL, encoding: .utf8)) ?? "WEBVTT\n"
                webVTT =
                    track.usesAdvancedTextStyling
                    ? ASSSubtitleConverter.convert(raw).webVTT
                    : raw
            }
            let cues = parseCues(webVTT, delay: delay)

            for segment in segments {
                try writeWebVTTSegment(segment, cues: cues, outputDirectory: outputDirectory)
            }
            try writeSubtitlePlaylist(segments: segments, outputDirectory: outputDirectory)
        }
    }

    /// Materializes a graphical subtitle as a temporary text track so the
    /// existing direct HDR/Dolby Vision route can keep copying the video while
    /// muxing a selectable `mov_text` subtitle into the MP4.
    static func materializeDirectTrack(
        _ track: SubtitleTrack,
        videoURL: URL,
        videoDuration: Double,
        outputDirectory: URL,
        maximumOCRFrames: Int? = nil,
        ocrProgress: (@Sendable (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async throws -> SubtitleTrack {
        guard track.usesBitmapOCR else { return track }
        let conversion = try await PGSSubtitleConverter.convert(
            track: track,
            videoURL: videoURL,
            videoDuration: videoDuration,
            maximumRenderedFrames: maximumOCRFrames,
            progress: ocrProgress
        )
        let outputURL = outputDirectory.appendingPathComponent("subtitles-ocr.vtt")
        try conversion.webVTT.write(to: outputURL, atomically: true, encoding: .utf8)
        return SubtitleTrack(
            streamIndex: nil,
            codec: "webvtt",
            language: track.language,
            title: track.title,
            isDefault: track.isDefault,
            isForced: track.isForced,
            isHearingImpaired: track.isHearingImpaired,
            externalPath: outputURL.path
        )
    }

    static func writeMasterPlaylist(
        probe: MediaProbe,
        audio: AudioTrack?,
        audioOutputMode: AudioOutputMode,
        subtitle: SubtitleTrack?,
        outputDirectory: URL
    ) throws {
        let fallbackAverageBandwidth = max(1_000_000, Int(probe.bitRate ?? 12_000_000))
        let measuredVideo = try renditionBandwidth(
            playlistName: "video.m3u8",
            outputDirectory: outputDirectory
        )
        let measuredAudio =
            audio == nil
            ? nil
            : try renditionBandwidth(
                playlistName: "audio.m3u8",
                outputDirectory: outputDirectory
            )
        let measuredAverage = measuredVideo.average + (measuredAudio?.average ?? 0)
        let measuredPeak = measuredVideo.peak + (measuredAudio?.peak ?? 0)
        let averageBandwidth = max(1_000_000, Int(ceil(measuredAverage)))
        let peakBandwidth = max(
            averageBandwidth + 1,
            Int(ceil(max(measuredPeak * 1.08, Double(fallbackAverageBandwidth) * 1.35)))
        )
        let resolution: String
        if let width = probe.width, let height = probe.height {
            resolution = ",RESOLUTION=\(width)x\(height)"
        } else {
            resolution = ""
        }
        let range = videoRange(probe)
        // fMP4, Dolby Vision compatibility metadata and I-frame renditions are
        // described using Apple's current multivariant-playlist vocabulary.
        let playlistVersion = 7
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:\(playlistVersion)",
            "#EXT-X-INDEPENDENT-SEGMENTS",
        ]
        if let audio {
            let name = quoted(audio.displayName)
            let language = quoted((audio.language ?? "und").replacingOccurrences(of: "_", with: "-"))
            let channels = audioChannels(audio: audio, outputMode: audioOutputMode)
            lines.append(
                "#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"audio\",NAME=\"\(name)\",LANGUAGE=\"\(language)\",AUTOSELECT=YES,DEFAULT=YES,CHANNELS=\"\(channels)\",URI=\"audio.m3u8\""
            )
        }
        if let subtitle {
            let name = quoted(subtitle.displayName)
            let language = quoted((subtitle.language ?? "und").replacingOccurrences(of: "_", with: "-"))
            let forced = subtitle.isForced ? "YES" : "NO"
            let characteristics =
                subtitle.isHearingImpaired
                ? ",CHARACTERISTICS=\"public.accessibility.transcribes-spoken-dialog,public.accessibility.describes-music-and-sound\""
                : ""
            lines.append(
                "#EXT-X-MEDIA:TYPE=SUBTITLES,GROUP-ID=\"subs\",NAME=\"\(name)\",LANGUAGE=\"\(language)\",AUTOSELECT=YES,DEFAULT=YES,FORCED=\(forced),URI=\"subtitles.m3u8\"\(characteristics)"
            )
        }

        var variant = "#EXT-X-STREAM-INF:BANDWIDTH=\(peakBandwidth),AVERAGE-BANDWIDTH=\(averageBandwidth)\(resolution)"
        let codecs = codecIdentifiers(
            probe: probe,
            audio: audio,
            audioOutputMode: audioOutputMode
        )
        let advertisedCodecs = subtitle == nil ? codecs : codecs + ["wvtt"]
        if !advertisedCodecs.isEmpty {
            variant += ",CODECS=\"\(advertisedCodecs.joined(separator: ","))\""
        }
        if let supplemental = supplementalCodecIdentifier(probe) {
            variant += ",SUPPLEMENTAL-CODECS=\"\(supplemental)\""
        }
        if let range { variant += ",VIDEO-RANGE=\(range)" }
        if let frameRate = frameRate(probe.frameRate) {
            variant += ",FRAME-RATE=\(String(format: "%.3f", frameRate))"
        }
        if audio != nil { variant += ",AUDIO=\"audio\"" }
        if subtitle != nil { variant += ",SUBTITLES=\"subs\"" }
        variant += ",CLOSED-CAPTIONS=NONE"
        lines += [variant, "video.m3u8"]

        try (lines.joined(separator: "\n") + "\n").write(
            to: outputDirectory.appendingPathComponent("master.m3u8"),
            atomically: true,
            encoding: .utf8
        )
    }

    static func validatePackage(
        outputDirectory: URL,
        expectedDuration: Double,
        hasAudio: Bool,
        hasSubtitles: Bool,
        requiresMasterPlaylist: Bool = true
    ) throws -> Double {
        let videoPlaylistURL = outputDirectory.appendingPathComponent("video.m3u8")
        let videoText = try String(contentsOf: videoPlaylistURL, encoding: .utf8)
        guard videoText.contains("#EXT-X-PLAYLIST-TYPE:VOD"),
            videoText.contains("#EXT-X-ENDLIST"),
            !videoText.contains("#EXT-X-DELETE")
        else {
            throw AirCillerError.invalidVODPackage("La lista de vídeo no está cerrada como VOD.")
        }

        let videoSegments = try parseVODPlaylist(at: videoPlaylistURL)
        let packagedDuration = videoSegments.reduce(0) { $0 + $1.duration }
        // En algunos MKV la duración del contenedor la alarga una pista de
        // subtítulos varios segundos después del último paquete audiovisual.
        let allowedDifference = max(15, (videoSegments.map(\.duration).max() ?? 0) * 1.5)
        guard abs(packagedDuration - expectedDuration) <= allowedDifference else {
            throw AirCillerError.invalidVODPackage(
                L10n.format(
                    "La duración preparada (%@) no coincide con el archivo (%@).",
                    TimeFormatting.duration(packagedDuration),
                    TimeFormatting.duration(expectedDuration))
            )
        }

        if videoText.contains("#EXT-X-MAP:") {
            let initURL = outputDirectory.appendingPathComponent("video-init.mp4")
            guard FileManager.default.fileExists(atPath: initURL.path) else {
                throw AirCillerError.invalidVODPackage("Falta la cabecera multimedia del vídeo.")
            }
        }
        for segment in videoSegments {
            guard
                FileManager.default.fileExists(
                    atPath: outputDirectory.appendingPathComponent(segment.fileName).path
                )
            else {
                throw AirCillerError.invalidVODPackage(
                    L10n.format("Falta el segmento de vídeo %@.", segment.fileName))
            }
        }

        if requiresMasterPlaylist {
            guard
                FileManager.default.fileExists(
                    atPath: outputDirectory.appendingPathComponent("master.m3u8").path
                )
            else {
                throw AirCillerError.invalidVODPackage("Falta la lista maestra del VOD.")
            }
        }

        if hasAudio {
            let audioPlaylistURL = outputDirectory.appendingPathComponent("audio.m3u8")
            let audioText = try String(contentsOf: audioPlaylistURL, encoding: .utf8)
            let videoTarget = videoText.components(separatedBy: .newlines)
                .first(where: { $0.hasPrefix("#EXT-X-TARGETDURATION:") })
            let audioTarget = audioText.components(separatedBy: .newlines)
                .first(where: { $0.hasPrefix("#EXT-X-TARGETDURATION:") })
            guard audioText.contains("#EXT-X-PLAYLIST-TYPE:VOD"),
                audioText.contains("#EXT-X-ENDLIST"),
                videoTarget != nil,
                videoTarget == audioTarget
            else {
                throw AirCillerError.invalidVODPackage("La lista de audio no está cerrada como VOD.")
            }
            let audioSegments = try parseVODPlaylist(at: audioPlaylistURL)
            let audioDuration = audioSegments.reduce(0) { $0 + $1.duration }
            let audioTolerance = max(15, (audioSegments.map(\.duration).max() ?? 0) * 1.5)
            guard !audioSegments.isEmpty, abs(audioDuration - expectedDuration) <= audioTolerance else {
                throw AirCillerError.invalidVODPackage(
                    "La pista de audio no cubre la duración completa de la película.")
            }
            guard abs(audioDuration - packagedDuration) < 0.000_5 else {
                throw AirCillerError.invalidVODPackage("Vídeo y audio no terminan en el mismo instante.")
            }
            if audioText.contains("#EXT-X-MAP:") {
                guard
                    FileManager.default.fileExists(
                        atPath: outputDirectory.appendingPathComponent("audio-init.mp4").path
                    )
                else {
                    throw AirCillerError.invalidVODPackage("Falta la cabecera multimedia del audio.")
                }
            }
            for segment in audioSegments {
                guard
                    FileManager.default.fileExists(
                        atPath: outputDirectory.appendingPathComponent(segment.fileName).path
                    )
                else {
                    throw AirCillerError.invalidVODPackage(
                        L10n.format("Falta el segmento de audio %@.", segment.fileName))
                }
            }
        }

        if hasSubtitles {
            let subtitlePlaylistURL = outputDirectory.appendingPathComponent("subtitles.m3u8")
            let subtitleText = try String(contentsOf: subtitlePlaylistURL, encoding: .utf8)
            guard subtitleText.contains("#EXT-X-PLAYLIST-TYPE:VOD"),
                subtitleText.contains("#EXT-X-ENDLIST")
            else {
                throw AirCillerError.invalidVODPackage("La pista de subtítulos no está cerrada como VOD.")
            }
            let subtitleSegments = try parseVODPlaylist(at: subtitlePlaylistURL)
            guard subtitleSegments.count == videoSegments.count else {
                throw AirCillerError.invalidVODPackage("Los subtítulos no cubren todos los segmentos de la película.")
            }
            for (video, subtitle) in zip(videoSegments, subtitleSegments) {
                guard abs(video.duration - subtitle.duration) < 0.002 else {
                    throw AirCillerError.invalidVODPackage("Los subtítulos no están alineados con el vídeo.")
                }
                let subtitleURL = outputDirectory.appendingPathComponent(subtitle.fileName)
                let vtt = try String(contentsOf: subtitleURL, encoding: .utf8)
                guard vtt.hasPrefix("WEBVTT\n"), vtt.contains("X-TIMESTAMP-MAP=") else {
                    throw AirCillerError.invalidVODPackage("Un segmento WebVTT no contiene su mapa temporal.")
                }
            }
        }

        return packagedDuration
    }

    private struct RenditionBandwidth {
        let average: Double
        let peak: Double
    }

    private static func renditionBandwidth(
        playlistName: String,
        outputDirectory: URL
    ) throws -> RenditionBandwidth {
        let segments = try parseVODPlaylist(
            at: outputDirectory.appendingPathComponent(playlistName)
        )
        guard !segments.isEmpty else {
            throw AirCillerError.invalidVODPackage(
                "La rendition no contiene segmentos para calcular su ancho de banda.")
        }

        var totalBytes: Double = 0
        var totalDuration: Double = 0
        var peak = 0.0
        for segment in segments {
            let url = outputDirectory.appendingPathComponent(segment.fileName)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard let number = attributes[.size] as? NSNumber, segment.duration > 0 else {
                throw AirCillerError.invalidVODPackage(
                    L10n.format("No se pudo medir el segmento %@.", segment.fileName)
                )
            }
            let bytes = number.doubleValue
            totalBytes += bytes
            totalDuration += segment.duration
            peak = max(peak, bytes * 8 / segment.duration)
        }
        guard totalDuration > 0 else {
            throw AirCillerError.invalidVODPackage("La rendition no tiene una duración válida.")
        }
        return RenditionBandwidth(
            average: totalBytes * 8 / totalDuration,
            peak: peak
        )
    }

    static func parseVODPlaylist(at url: URL) throws -> [HLSSegment] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parseVODPlaylistText(text)
    }

    private static func parseVODPlaylistText(_ text: String) throws -> [HLSSegment] {
        let lines =
            text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        var segments: [HLSSegment] = []
        var pendingDuration: Double?
        var startTime = 0.0

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#EXTINF:") {
                let value = line.dropFirst("#EXTINF:".count).split(separator: ",", maxSplits: 1).first
                pendingDuration = value.flatMap { Double($0) }
                continue
            }
            guard !line.isEmpty, !line.hasPrefix("#"), let duration = pendingDuration else { continue }
            let segment = HLSSegment(
                index: segments.count,
                duration: duration,
                startTime: startTime,
                fileName: line
            )
            segments.append(segment)
            startTime += duration
            pendingDuration = nil
        }
        return segments
    }

    private static func replacingLastSegmentDuration(in text: String, adjustment: Double) throws -> String {
        var lines = text.components(separatedBy: "\n")
        guard let index = lines.lastIndex(where: { $0.hasPrefix("#EXTINF:") }),
            let value = lines[index]
                .dropFirst("#EXTINF:".count)
                .split(separator: ",", maxSplits: 1)
                .first
                .flatMap({ Double($0) })
        else {
            throw AirCillerError.invalidVODPackage("No se pudo alinear el final de vídeo y audio.")
        }
        let aligned = value + adjustment
        guard aligned > 0 else {
            throw AirCillerError.invalidVODPackage("La corrección temporal de la última rendition no es válida.")
        }
        lines[index] = "#EXTINF:\(String(format: "%.6f", aligned)),"
        return lines.joined(separator: "\n")
    }

    private static func normalizedVODPlaylist(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        if let versionIndex = lines.firstIndex(where: { $0.hasPrefix("#EXT-X-VERSION:") }) {
            // Apple uses version 6 in the multivariant playlist and version 7
            // in fMP4 media playlists. Forcing EXT-X-MAP renditions down to 6
            // makes current tvOS stop after reading the media playlist, before
            // it requests the initialisation segment.
            let usesFragmentedMP4 = lines.contains(where: { $0.hasPrefix("#EXT-X-MAP:") })
            lines[versionIndex] = "#EXT-X-VERSION:\(usesFragmentedMP4 ? 7 : 6)"
        }
        lines.removeAll(where: { $0 == "#EXT-X-ALLOW-CACHE:NO" })
        return lines.joined(separator: "\n")
    }

    private static func extractWebVTT(
        track: SubtitleTrack,
        videoURL: URL,
        outputURL: URL
    ) async throws {
        guard let ffmpegURL = Executables.find("ffmpeg") else {
            throw AirCillerError.ffmpegMissing
        }

        let inputURL = track.externalPath.map(URL.init(fileURLWithPath:)) ?? videoURL
        let process = Process()
        process.executableURL = ffmpegURL
        var arguments = ["-hide_banner", "-nostdin", "-loglevel", "error", "-i", inputURL.path, "-map"]
        if track.externalPath != nil {
            arguments.append("0:0")
        } else if let streamIndex = track.streamIndex {
            arguments.append("0:\(streamIndex)")
        } else {
            throw AirCillerError.unsupportedSubtitle("No se encontró la pista de subtítulos elegida.")
        }
        if track.usesAdvancedTextStyling {
            arguments += ["-c:s", "ass", "-f", "ass"]
        } else {
            arguments += ["-c:s", "webvtt", "-f", "webvtt"]
        }
        arguments += ["-y", outputURL.path]
        process.arguments = arguments

        let errors = Pipe()
        let errorBuffer = ProcessDataBuffer(maximumBytes: 64_000)
        errors.fileHandleForReading.readabilityHandler = { handle in
            errorBuffer.append(handle.availableData)
        }
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        let status = try await CancellableProcess(process).run {
            try? errors.fileHandleForWriting.close()
        }
        errors.fileHandleForReading.readabilityHandler = nil
        errorBuffer.append(errors.fileHandleForReading.readDataToEndOfFile())

        guard status == 0 else {
            let data = errorBuffer.snapshot
            let message =
                String(data: data, encoding: .utf8)
                ?? L10n.text("FFmpeg no pudo preparar los subtítulos.")
            throw AirCillerError.subtitlePreparationFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func writeWebVTTSegment(
        _ segment: HLSSegment,
        cues: [WebVTTCue],
        outputDirectory: URL
    ) throws {
        let endTime = segment.startTime + segment.duration
        let overlapping = cues.filter { cue in
            cue.end > segment.startTime && cue.start < endTime
        }
        var blocks = ["WEBVTT\nX-TIMESTAMP-MAP=LOCAL:00:00:00.000,MPEGTS:0"]

        for cue in overlapping {
            // RFC 8216 exige conservar el intervalo total del cue aunque cruce
            // los límites del segmento; todos los tiempos permanecen absolutos.
            let settings = cue.settings.isEmpty ? "" : " \(cue.settings)"
            let timing = "\(formatTimestamp(cue.start)) --> \(formatTimestamp(cue.end))\(settings)"
            blocks.append(([timing] + cue.payload).joined(separator: "\n"))
        }

        let fileName = String(format: "subtitles-%08d.vtt", segment.index)
        try (blocks.joined(separator: "\n\n") + "\n").write(
            to: outputDirectory.appendingPathComponent(fileName),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func writeSubtitlePlaylist(segments: [HLSSegment], outputDirectory: URL) throws {
        let targetDuration = max(1, Int(ceil(segments.map(\.duration).max() ?? 1)))
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:6",
            "#EXT-X-TARGETDURATION:\(targetDuration)",
            "#EXT-X-MEDIA-SEQUENCE:0",
            "#EXT-X-PLAYLIST-TYPE:VOD",
        ]
        for segment in segments {
            lines.append("#EXTINF:\(String(format: "%.6f", segment.duration)),")
            lines.append(String(format: "subtitles-%08d.vtt", segment.index))
        }
        lines.append("#EXT-X-ENDLIST")
        try (lines.joined(separator: "\n") + "\n").write(
            to: outputDirectory.appendingPathComponent("subtitles.m3u8"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func parseCues(_ source: String, delay: Double) -> [WebVTTCue] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n")
        let blocks = normalized.components(separatedBy: "\n\n")
        var cues: [WebVTTCue] = []

        for block in blocks {
            let lines = block.components(separatedBy: "\n")
            guard let timingIndex = lines.firstIndex(where: { $0.contains(" --> ") }) else { continue }
            let parts = lines[timingIndex].components(separatedBy: " --> ")
            guard parts.count == 2,
                let originalStart = parseTimestamp(parts[0]),
                let originalEnd = parseTimestamp(parts[1].split(separator: " ").first.map(String.init) ?? parts[1])
            else {
                continue
            }

            let shiftedStart = originalStart + delay
            let shiftedEnd = originalEnd + delay
            guard shiftedEnd > 0, shiftedEnd > shiftedStart else { continue }
            let payload = Array(lines.dropFirst(timingIndex + 1))
            guard !payload.isEmpty else { continue }
            let endAndSettings = parts[1].split(whereSeparator: { $0.isWhitespace })
            let settings = endAndSettings.dropFirst().joined(separator: " ")
            cues.append(
                WebVTTCue(
                    start: max(0, shiftedStart),
                    end: shiftedEnd,
                    settings: settings,
                    payload: payload
                )
            )
        }
        return cues
    }

    private static func parseTimestamp(_ value: String) -> Double? {
        let fields = value.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard fields.count == 2 || fields.count == 3,
            let secondsField = fields.last,
            let seconds = Double(secondsField),
            let minutes = Double(fields[fields.count - 2]),
            let hours = fields.count == 3 ? Double(fields[0]) : 0,
            minutes >= 0, minutes < 60,
            seconds >= 0, seconds < 60,
            hours >= 0
        else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }

    private static func formatTimestamp(_ seconds: Double) -> String {
        let milliseconds = Int((max(0, seconds) * 1000).rounded())
        let hours = milliseconds / 3_600_000
        let minutes = (milliseconds % 3_600_000) / 60_000
        let remainingSeconds = (milliseconds % 60_000) / 1000
        let remainingMilliseconds = milliseconds % 1000
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, remainingSeconds, remainingMilliseconds)
    }

    private static func quoted(_ value: String) -> String {
        value.replacingOccurrences(of: "\"", with: "'")
    }

    private static func codecIdentifiers(
        probe: MediaProbe,
        audio: AudioTrack?,
        audioOutputMode: AudioOutputMode
    ) -> [String] {
        var values: [String] = []
        if supplementalCodecIdentifier(probe) != nil {
            values.append(hevcCodecIdentifier(probe))
        } else if probe.isDolbyVision,
            let profile = probe.dolbyVisionProfile,
            let level = probe.dolbyVisionLevel
        {
            values.append(String(format: "dvh1.%02d.%02d", profile, level))
        } else if probe.videoCodec.lowercased() == "hevc" {
            values.append(hevcCodecIdentifier(probe))
        } else if probe.videoCodec.lowercased() == "h264" {
            values.append("avc1")
        }
        if audio != nil {
            switch audioOutputMode {
            case .compatible:
                values.append("ec-3")
            case .stereo:
                values.append("mp4a.40.2")
            case .original:
                switch audio?.codec.lowercased() {
                case "aac": values.append("mp4a.40.2")
                case "ac3": values.append("ac-3")
                case "eac3": values.append("ec-3")
                case "alac": values.append("alac")
                default: break
                }
            }
        }
        return values
    }

    private static func supplementalCodecIdentifier(_ probe: MediaProbe) -> String? {
        guard probe.dolbyVisionProfile == 8,
            let level = probe.dolbyVisionLevel,
            let compatibilityID = probe.dolbyVisionCompatibilityID
        else { return nil }
        let brand: String
        switch compatibilityID {
        case 1: brand = "db1p"
        case 4: brand = "db4h"
        default: return nil
        }
        return String(format: "dvh1.08.%02d/%@", level, brand)
    }

    private static func hevcCodecIdentifier(_ probe: MediaProbe) -> String {
        if let identifier = probe.hevcCodecIdentifier { return identifier }
        guard probe.videoProfile?.localizedCaseInsensitiveContains("Main 10") == true else {
            return "hvc1"
        }
        let level = probe.videoLevel ?? ((probe.height ?? 0) > 1080 ? 150 : 123)
        return "hvc1.2.4.L\(level).B0"
    }

    private static func audioChannels(audio: AudioTrack, outputMode: AudioOutputMode) -> String {
        switch outputMode {
        case .stereo:
            return "2"
        case .compatible:
            return String(min(audio.channels ?? 6, 6))
        case .original:
            if audio.isAtmos { return "16/JOC" }
            return String(audio.channels ?? 2)
        }
    }

    private static func videoRange(_ probe: MediaProbe) -> String? {
        if probe.isDolbyVision || probe.colorTransfer?.lowercased() == "smpte2084" { return "PQ" }
        if probe.colorTransfer?.lowercased() == "arib-std-b67" { return "HLG" }
        return nil
    }

    private static func frameRate(_ value: String?) -> Double? {
        guard let value else { return nil }
        let fields = value.split(separator: "/")
        if fields.count == 2,
            let numerator = Double(fields[0]),
            let denominator = Double(fields[1]),
            denominator != 0
        {
            return numerator / denominator
        }
        return Double(value)
    }
}

private struct WebVTTCue: Sendable {
    let start: Double
    let end: Double
    let settings: String
    let payload: [String]
}
