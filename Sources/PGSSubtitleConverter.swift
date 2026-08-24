import CoreGraphics
import Foundation
import ImageIO

struct PGSSubtitleConversion: Sendable {
    let webVTT: String
    let cueCount: Int
    let averageConfidence: Float
    let usedCache: Bool
}

/// Converts PGS and VobSub bitmap subtitles to selectable WebVTT text.
///
/// FFmpeg is used only to decode the selected subtitle stream into transparent
/// PNG frames. Apple Vision then performs local OCR. The movie itself is never
/// decoded, modified, uploaded or burned into the picture.
enum PGSSubtitleConverter {
    private static let cacheVersion = 1

    static func convert(
        track: SubtitleTrack,
        videoURL: URL,
        videoDuration: Double,
        maximumRenderedFrames: Int? = nil,
        cacheDirectory explicitCacheDirectory: URL? = nil,
        progress: (@Sendable (_ completed: Int, _ total: Int) -> Void)? = nil
    ) async throws -> PGSSubtitleConversion {
        let codec = track.codec.lowercased()
        guard ["hdmv_pgs_subtitle", "dvd_subtitle"].contains(codec),
            let streamIndex = track.streamIndex
        else {
            throw AirCillerError.unsupportedSubtitle(
                "Esta conversión local solo admite pistas gráficas PGS y VobSub."
            )
        }

        let cacheDirectory = try explicitCacheDirectory ?? defaultCacheDirectory()
        let cacheURL = cacheDirectory.appendingPathComponent(
            cacheFileName(track: track, videoURL: videoURL)
        )
        if maximumRenderedFrames == nil,
            let cached = try? String(contentsOf: cacheURL, encoding: .utf8),
            cached.hasPrefix("WEBVTT\n"),
            let metadata = cacheMetadata(in: cached)
        {
            AirCillerStorage.touchCachedSubtitle(cacheURL)
            progress?(1, 1)
            return PGSSubtitleConversion(
                webVTT: cached,
                cueCount: metadata.cueCount,
                averageConfidence: metadata.averageConfidence,
                usedCache: true
            )
        }

        let workingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-Bitmap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: workingDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: workingDirectory) }

        let frameBounds = try await renderFrames(
            videoURL: videoURL,
            streamIndex: streamIndex,
            codec: codec,
            outputDirectory: workingDirectory,
            maximumFrames: maximumRenderedFrames
        )
        try Task.checkCancellation()

        let groups = try frameGroups(
            in: workingDirectory,
            videoDuration: videoDuration,
            isTruncated: maximumRenderedFrames != nil,
            frameBounds: frameBounds
        )
        let visibleGroups = groups.filter { $0.bounds != nil }
        guard !visibleGroups.isEmpty else {
            throw AirCillerError.subtitlePreparationFailed(
                "La pista gráfica no produjo ninguna imagen de subtítulo."
            )
        }

        let recognitionLanguages = preferredRecognitionLanguages(for: track.language)
        progress?(0, visibleGroups.count)
        let cues = try await recognize(
            groups: visibleGroups,
            recognitionLanguages: recognitionLanguages,
            progress: progress
        )

        let mergedCues = mergeAdjacentDuplicates(cues)
        guard !mergedCues.isEmpty else {
            throw AirCillerError.subtitlePreparationFailed(
                "Apple Vision no encontró texto legible en la pista gráfica elegida."
            )
        }
        let averageConfidence =
            mergedCues.reduce(Float.zero) { $0 + $1.confidence }
            / Float(mergedCues.count)
        let webVTT = makeWebVTT(
            cues: mergedCues,
            averageConfidence: averageConfidence
        )

        if maximumRenderedFrames == nil {
            try FileManager.default.createDirectory(
                at: cacheDirectory,
                withIntermediateDirectories: true
            )
            try webVTT.write(to: cacheURL, atomically: true, encoding: .utf8)
            _ = try AirCillerStorage.pruneFiles(
                in: cacheDirectory,
                limitBytes: AirCillerStorage.subtitleCacheLimitBytes
            )
        }
        return PGSSubtitleConversion(
            webVTT: webVTT,
            cueCount: mergedCues.count,
            averageConfidence: averageConfidence,
            usedCache: false
        )
    }

    private struct FrameGroup: Sendable {
        let start: Double
        let end: Double
        let imageURL: URL
        let bounds: CGRect?
    }

    private struct SubtitleLayout: Sendable {
        let canvasWidth: Int
        let canvasHeight: Int
        let bounds: CGRect
    }

    private struct RenderedSubtitle {
        let image: CGImage
        let layout: SubtitleLayout
    }

    private struct RecognizedCue: Sendable {
        let start: Double
        var end: Double
        let settings: String
        let text: String
        let confidence: Float
    }

    private struct CacheMetadata {
        let cueCount: Int
        let averageConfidence: Float
    }

    private static func renderFrames(
        videoURL: URL,
        streamIndex: Int,
        codec: String,
        outputDirectory: URL,
        maximumFrames: Int?
    ) async throws -> [Int64: CGRect] {
        guard let ffmpegURL = Executables.find("ffmpeg") else {
            throw AirCillerError.ffmpegMissing
        }
        let outputPattern = outputDirectory.appendingPathComponent("frame-%016d.png").path

        let process = Process()
        process.executableURL = ffmpegURL
        var arguments = ["-hide_banner", "-nostdin", "-loglevel", "info"]
        if codec == "hdmv_pgs_subtitle" {
            let canvasSize = try await detectedCanvasSize(
                ffmpegURL: ffmpegURL,
                videoURL: videoURL,
                streamIndex: streamIndex
            )
            arguments += ["-canvas_size", "\(canvasSize.width)x\(canvasSize.height)"]
        }
        arguments += [
            "-i", videoURL.path,
            "-filter_complex",
            "[0:\(streamIndex)]split=2[bitmap][bounds];[bounds]alphaextract,bbox=min_val=1,nullsink",
            "-map", "[bitmap]",
        ]
        if let maximumFrames, maximumFrames > 0 {
            arguments += ["-frames:v", String(maximumFrames)]
        }
        arguments += [
            "-c:v", "png",
            "-fps_mode", "passthrough",
            "-frame_pts", "1",
            "-y", outputPattern,
        ]
        process.arguments = arguments

        let errors = Pipe()
        let errorBuffer = ProcessDataBuffer(maximumBytes: 16_000_000)
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
            let message =
                String(data: errorBuffer.snapshot, encoding: .utf8)
                ?? "FFmpeg no pudo decodificar la pista gráfica."
            throw AirCillerError.subtitlePreparationFailed(
                message.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return parsedFrameBounds(from: errorBuffer.snapshot)
    }

    private static func detectedCanvasSize(
        ffmpegURL: URL,
        videoURL: URL,
        streamIndex: Int
    ) async throws -> (width: Int, height: Int) {
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-hide_banner", "-nostdin", "-loglevel", "warning",
            "-i", videoURL.path,
            "-filter_complex", "[0:\(streamIndex)]null[pgs]",
            "-map", "[pgs]",
            "-frames:v", "2",
            "-f", "null", "-",
        ]
        let errors = Pipe()
        let errorBuffer = ProcessDataBuffer(maximumBytes: 256_000)
        errors.fileHandleForReading.readabilityHandler = { handle in
            errorBuffer.append(handle.availableData)
        }
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        _ = try await CancellableProcess(process).run {
            try? errors.fileHandleForWriting.close()
        }
        errors.fileHandleForReading.readabilityHandler = nil
        errorBuffer.append(errors.fileHandleForReading.readDataToEndOfFile())
        if let text = String(data: errorBuffer.snapshot, encoding: .utf8),
            let expression = try? NSRegularExpression(
                pattern: #"incoming frame - w:\s*([0-9]+) h:\s*([0-9]+)"#
            ),
            let match = expression.matches(
                in: text,
                range: NSRange(text.startIndex..., in: text)
            ).last,
            let widthRange = Range(match.range(at: 1), in: text),
            let heightRange = Range(match.range(at: 2), in: text),
            let width = Int(text[widthRange]),
            let height = Int(text[heightRange]),
            width > 0, height > 0
        {
            return (width, height)
        }
        return try await detectedVideoSize(videoURL: videoURL)
    }

    private static func detectedVideoSize(videoURL: URL) async throws -> (width: Int, height: Int) {
        guard let ffprobeURL = Executables.find("ffprobe") else {
            throw AirCillerError.ffprobeMissing
        }
        let process = Process()
        process.executableURL = ffprobeURL
        process.arguments = [
            "-v", "error",
            "-select_streams", "v:0",
            "-show_entries", "stream=width,height",
            "-of", "csv=p=0:s=x",
            videoURL.path,
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        let status = try await CancellableProcess(process).run {
            try? output.fileHandleForWriting.close()
        }
        let text = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )?.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = text?.split(separator: "x", maxSplits: 1).compactMap { Int($0) } ?? []
        guard status == 0,
            values.count == 2,
            values[0] > 0,
            values[1] > 0
        else {
            throw AirCillerError.subtitlePreparationFailed(
                "FFmpeg no pudo determinar el lienzo de la pista gráfica."
            )
        }
        return (values[0], values[1])
    }

    private static func frameGroups(
        in directory: URL,
        videoDuration: Double,
        isTruncated: Bool,
        frameBounds: [Int64: CGRect]
    ) throws -> [FrameGroup] {
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        let timedFiles = files.compactMap { url -> (url: URL, time: Double)? in
            guard url.pathExtension.lowercased() == "png",
                let time = frameTime(from: url)
            else { return nil }
            return (url, time)
        }.sorted { $0.time < $1.time }
        guard let first = timedFiles.first else { return [] }

        var groups: [FrameGroup] = []
        var currentURL = first.url
        var currentData = try Data(contentsOf: first.url, options: .mappedIfSafe)
        var currentStart = first.time

        for frame in timedFiles.dropFirst() {
            try Task.checkCancellation()
            let data = try Data(contentsOf: frame.url, options: .mappedIfSafe)
            guard data != currentData else { continue }
            if frame.time > currentStart {
                groups.append(
                    FrameGroup(
                        start: currentStart,
                        end: frame.time,
                        imageURL: currentURL,
                        bounds: frameBounds[frameTimestamp(currentStart)]
                    )
                )
            }
            currentURL = frame.url
            currentData = data
            currentStart = frame.time
        }

        let fallbackEnd =
            isTruncated
            ? currentStart + 5
            : max(videoDuration, currentStart + 5)
        groups.append(
            FrameGroup(
                start: currentStart,
                end: fallbackEnd,
                imageURL: currentURL,
                bounds: frameBounds[frameTimestamp(currentStart)]
            )
        )
        return groups
    }

    /// The automatically inserted subtitle-to-video bridge uses AV_TIME_BASE,
    /// hence `-frame_pts 1` writes microseconds into each filename.
    private static func frameTime(from url: URL) -> Double? {
        let stem = url.deletingPathExtension().lastPathComponent
        guard let value = stem.split(separator: "-").last.flatMap({ Int64($0) }) else { return nil }
        return Double(value) / 1_000_000
    }

    private static func frameTimestamp(_ seconds: Double) -> Int64 {
        Int64((seconds * 1_000_000).rounded())
    }

    private static func parsedFrameBounds(from data: Data) -> [Int64: CGRect] {
        guard let text = String(data: data, encoding: .utf8),
            let expression = try? NSRegularExpression(
                pattern: #"pts:(-?[0-9]+).*?x1:([0-9]+) x2:([0-9]+) y1:([0-9]+) y2:([0-9]+)"#
            )
        else { return [:] }
        let range = NSRange(text.startIndex..., in: text)
        var values: [Int64: CGRect] = [:]
        for match in expression.matches(in: text, range: range) where match.numberOfRanges == 6 {
            let captures = (1..<6).compactMap { index -> Int64? in
                guard let range = Range(match.range(at: index), in: text) else { return nil }
                return Int64(text[range])
            }
            guard captures.count == 5 else { continue }
            let x1 = captures[1]
            let x2 = captures[2]
            let y1 = captures[3]
            let y2 = captures[4]
            values[captures[0]] = CGRect(
                x: Int(x1),
                y: Int(y1),
                width: Int(x2 - x1 + 1),
                height: Int(y2 - y1 + 1)
            )
        }
        return values
    }

    private static func recognize(
        groups: [FrameGroup],
        recognitionLanguages: [String],
        progress: (@Sendable (_ completed: Int, _ total: Int) -> Void)?
    ) async throws -> [RecognizedCue] {
        let concurrency = min(4, groups.count)
        return try await withThrowingTaskGroup(of: IndexedCue.self) { taskGroup in
            var nextIndex = 0
            for _ in 0..<concurrency {
                let index = nextIndex
                let frame = groups[index]
                taskGroup.addTask {
                    IndexedCue(
                        index: index,
                        cue: try await recognize(
                            group: frame,
                            recognitionLanguages: recognitionLanguages
                        )
                    )
                }
                nextIndex += 1
            }

            var completed = 0
            var recognized: [IndexedCue] = []
            recognized.reserveCapacity(groups.count)
            while let result = try await taskGroup.next() {
                recognized.append(result)
                completed += 1
                progress?(completed, groups.count)
                if nextIndex < groups.count {
                    let index = nextIndex
                    let frame = groups[index]
                    taskGroup.addTask {
                        IndexedCue(
                            index: index,
                            cue: try await recognize(
                                group: frame,
                                recognitionLanguages: recognitionLanguages
                            )
                        )
                    }
                    nextIndex += 1
                }
            }
            return
                recognized
                .sorted { $0.index < $1.index }
                .compactMap(\.cue)
        }
    }

    private static func recognize(
        group: FrameGroup,
        recognitionLanguages: [String]
    ) async throws -> RecognizedCue? {
        try Task.checkCancellation()
        guard let bounds = group.bounds,
            let rendered = try renderedSubtitle(at: group.imageURL, bounds: bounds)
        else {
            return nil
        }
        let result = try await SubtitleOCRService.recognize(
            in: rendered.image,
            preferredLanguages: recognitionLanguages
        )
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, group.end > group.start else { return nil }
        return RecognizedCue(
            start: group.start,
            end: group.end,
            settings: cueSettings(for: rendered.layout),
            text: escapedWebVTTText(text),
            confidence: result.confidence
        )
    }

    private struct IndexedCue: Sendable {
        let index: Int
        let cue: RecognizedCue?
    }

    private static func renderedSubtitle(
        at url: URL,
        bounds: CGRect
    ) throws -> RenderedSubtitle? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw AirCillerError.subtitlePreparationFailed(
                "No se pudo abrir una imagen temporal de la pista gráfica."
            )
        }
        let padding = max(12, Int((Double(image.height) * 0.018).rounded()))
        let crop = bounds.insetBy(dx: -CGFloat(padding), dy: -CGFloat(padding))
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            .integral
        guard let cropped = image.cropping(to: crop) else {
            throw AirCillerError.subtitlePreparationFailed(
                "No se pudo recortar una imagen temporal de la pista gráfica."
            )
        }
        return RenderedSubtitle(
            image: cropped,
            layout: SubtitleLayout(
                canvasWidth: image.width,
                canvasHeight: image.height,
                bounds: bounds
            )
        )
    }

    private static func cueSettings(for layout: SubtitleLayout) -> String {
        let width = max(1, Double(layout.canvasWidth))
        let height = max(1, Double(layout.canvasHeight))
        let position = clamp(Double(layout.bounds.midX) / width * 100)
        // The decoded PNG rows and WebVTT percentage lines both run from the
        // top of the composition. Keeping that coordinate preserves captions
        // authored near the top or bottom of the Blu-ray frame.
        let line = clamp(Double(layout.bounds.midY) / height * 100)
        let textWidth = Double(layout.bounds.width) / width * 100
        let size = min(96, max(30, textWidth + 12))
        return
            "line:\(percentage(line))%,center position:\(percentage(position))%,center align:center size:\(percentage(size))%"
    }

    private static func mergeAdjacentDuplicates(_ cues: [RecognizedCue]) -> [RecognizedCue] {
        var merged: [RecognizedCue] = []
        for cue in cues.sorted(by: { $0.start < $1.start }) {
            if var previous = merged.last,
                previous.text == cue.text,
                previous.settings == cue.settings,
                cue.start <= previous.end + 0.15
            {
                previous.end = max(previous.end, cue.end)
                merged[merged.count - 1] = previous
            } else {
                merged.append(cue)
            }
        }
        return merged
    }

    private static func makeWebVTT(
        cues: [RecognizedCue],
        averageConfidence: Float
    ) -> String {
        var blocks = [
            "WEBVTT",
            "NOTE AirCiller Bitmap OCR v\(cacheVersion); cues=\(cues.count); confidence=\(String(format: "%.4f", averageConfidence))",
        ]
        blocks += cues.map { cue in
            "\(timestamp(cue.start)) --> \(timestamp(cue.end)) \(cue.settings)\n\(cue.text)"
        }
        return blocks.joined(separator: "\n\n") + "\n"
    }

    private static func cacheMetadata(in webVTT: String) -> CacheMetadata? {
        let supportedPrefixes = [
            "NOTE AirCiller Bitmap OCR v\(cacheVersion);",
            "NOTE AirCiller PGS OCR v\(cacheVersion);",
        ]
        guard
            let note = webVTT.components(separatedBy: .newlines).first(where: { line in
                supportedPrefixes.contains(where: line.hasPrefix)
            })
        else { return nil }
        let fields = note.split(separator: ";").reduce(into: [String: String]()) { result, field in
            let pair = field.split(separator: "=", maxSplits: 1).map(String.init)
            if pair.count == 2 {
                result[pair[0].trimmingCharacters(in: .whitespaces)] = pair[1]
            }
        }
        guard let cueText = fields["cues"], let cueCount = Int(cueText),
            let confidenceText = fields["confidence"],
            let averageConfidence = Float(confidenceText)
        else { return nil }
        return CacheMetadata(cueCount: cueCount, averageConfidence: averageConfidence)
    }

    private static func defaultCacheDirectory() throws -> URL {
        try AirCillerStorage.subtitleCacheDirectory()
    }

    private static func cacheFileName(track: SubtitleTrack, videoURL: URL) -> String {
        let attributes = try? FileManager.default.attributesOfItem(atPath: videoURL.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let identity = [
            track.codec.lowercased() == "dvd_subtitle" ? "v2" : "v\(cacheVersion)",
            videoURL.standardizedFileURL.path,
            String(size),
            String(format: "%.3f", modified),
            String(track.streamIndex ?? -1),
            track.codec.lowercased(),
            track.language ?? "und",
        ].joined(separator: "|")
        return String(format: "%016llx.vtt", fnv1a64(identity))
    }

    private static func fnv1a64(_ value: String) -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return hash
    }

    private static func preferredRecognitionLanguages(for language: String?) -> [String] {
        guard let language else { return [] }
        switch language.lowercased().split(separator: "-").first.map(String.init) {
        case "eng", "en": return ["en-US"]
        case "spa", "es": return ["es-ES"]
        case "cat", "ca": return ["ca-ES"]
        case "fra", "fre", "fr": return ["fr-FR"]
        case "deu", "ger", "de": return ["de-DE"]
        case "ita", "it": return ["it-IT"]
        case "por", "pt": return ["pt-PT"]
        case "jpn", "ja": return ["ja-JP"]
        case "kor", "ko": return ["ko-KR"]
        case "zho", "chi", "zh": return ["zh-Hans"]
        default: return []
        }
    }

    private static func escapedWebVTTText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func timestamp(_ seconds: Double) -> String {
        let milliseconds = Int((max(0, seconds) * 1000).rounded())
        return String(
            format: "%02d:%02d:%02d.%03d",
            milliseconds / 3_600_000,
            (milliseconds % 3_600_000) / 60_000,
            (milliseconds % 60_000) / 1000,
            milliseconds % 1000
        )
    }

    private static func percentage(_ value: Double) -> String {
        let rounded = (value * 1000).rounded() / 1000
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(rounded)
    }

    private static func clamp(_ value: Double) -> Double {
        min(98, max(2, value))
    }
}
