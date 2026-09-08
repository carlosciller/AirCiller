import Foundation

/// A local VobSub index and its bitmap companion. Stream order follows the
/// demuxer: the first timestamp for an ID creates a stream; empty IDs do not.
struct ExternalVobSub {
    let indexURL: URL
    let bitmapURL: URL
    let tracks: [SubtitleTrack]

    private static let idPattern = try! NSRegularExpression(
        pattern: #"^id:[ \t]*([A-Za-z-]{2,3}),[ \t]*index:[ \t]*([0-9]+)[ \t]*$"#)
    private static let timePattern = try! NSRegularExpression(
        pattern:
            #"^timestamp:[ \t]*([0-9]{2}):([0-9]{2}):([0-9]{2}):([0-9]{3}),[ \t]*filepos:[ \t]*([0-9A-Fa-f]+)[ \t]*$"#)

    init(url: URL) throws {
        guard ["idx", "sub"].contains(url.pathExtension.lowercased()) else { throw Self.invalidIndex }
        let directory = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        let siblings = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        func companion(_ ext: String) throws -> URL {
            let matches = siblings.filter {
                $0.deletingPathExtension().lastPathComponent == stem && $0.pathExtension.lowercased() == ext
            }
            guard matches.count == 1, let file = matches.first else {
                throw AirCillerError.unsupportedSubtitle(
                    "VobSub necesita un único archivo .idx y su .sub con el mismo nombre, en la misma carpeta.")
            }
            return file
        }
        indexURL = try companion("idx")
        bitmapURL = try companion("sub")
        let indexSize = try Self.regularFileSize(indexURL)
        let bitmapSize = try Self.regularFileSize(bitmapURL)
        guard (1...4_194_304).contains(indexSize), (4...268_435_456).contains(bitmapSize) else {
            throw AirCillerError.unsupportedSubtitle("El par VobSub está vacío o supera el límite de lectura segura.")
        }
        let bitmap = try FileHandle(forReadingFrom: bitmapURL)
        defer { try? bitmap.close() }
        guard try bitmap.read(upToCount: 4) == Data([0, 0, 1, 0xBA]) else { throw Self.invalidIndex }
        let file = try FileHandle(forReadingFrom: indexURL)
        defer { try? file.close() }
        let data = try file.read(upToCount: 4_194_305) ?? Data()
        guard data.count <= 4_194_304,
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
            text.hasPrefix("# VobSub index file, v7")
        else { throw Self.invalidIndex }
        var selectedID: Int?
        var language = "und"
        var title: String?
        var defaultIndex = 0
        var paletteFound = false
        var canvasFound = false
        var ids: [Int] = []
        var metadata: [(language: String, title: String?)] = []
        for line in text.components(separatedBy: .newlines) {
            guard line.utf8.count < 1024 else { throw Self.invalidIndex }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard line.first != " " && line.first != "\t" || trimmed.isEmpty || trimmed.hasPrefix("#") else {
                throw Self.invalidIndex
            }
            if line.hasPrefix("id:") {
                guard let fields = Self.fields(line, pattern: Self.idPattern),
                    let id = Int(fields[1]), (0..<32).contains(id)
                else { throw Self.invalidIndex }
                selectedID = id
                language = fields[0].lowercased()
                title = nil
            } else if line.hasPrefix("alt:") {
                title = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("timestamp:") {
                guard let id = selectedID, let fields = Self.fields(line, pattern: Self.timePattern),
                    let minutes = Int(fields[1]), minutes < 60,
                    let seconds = Int(fields[2]), seconds < 60,
                    let position = Int64(fields[4], radix: 16), position < bitmapSize
                else { throw Self.invalidIndex }
                if !ids.contains(id) {
                    ids.append(id)
                    metadata.append((language, title))
                }
            } else if line.hasPrefix("langidx:") {
                guard let value = Int(line.dropFirst(8).trimmingCharacters(in: .whitespaces)), value >= 0 else {
                    throw Self.invalidIndex
                }
                defaultIndex = value
            } else if line.hasPrefix("palette:") && selectedID == nil {
                let colors = line.dropFirst(8).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                guard colors.count == 16,
                    colors.allSatisfy({ $0.count == 6 && UInt32($0, radix: 16) != nil })
                else { throw Self.invalidIndex }
                paletteFound = true
            } else if line.hasPrefix("size:") && selectedID == nil {
                let dimensions = line.dropFirst(5).trimmingCharacters(in: .whitespaces).split(separator: "x")
                guard dimensions.count == 2,
                    dimensions.allSatisfy({ Int($0).map { (1...4096).contains($0) } == true })
                else { throw Self.invalidIndex }
                canvasFound = true
            }
        }
        guard !ids.isEmpty, paletteFound, canvasFound else { throw Self.invalidIndex }
        let indexPath = indexURL.path
        tracks = metadata.enumerated().map { offset, info in
            SubtitleTrack(
                // MP4's language field needs ISO 639-2. The IDX demuxer exposes
                // two-letter codes; passing those through drops the MP4 language.
                streamIndex: offset, codec: "dvd_subtitle",
                language: Locale.LanguageCode(info.language).identifier(.alpha3) ?? "und",
                title: info.title, isDefault: offset == defaultIndex,
                isForced: stem.localizedCaseInsensitiveContains("forced"),
                isHearingImpaired: stem.localizedCaseInsensitiveContains("sdh"), externalPath: indexPath)
        }
    }

    private static var invalidIndex: AirCillerError {
        .unsupportedSubtitle("El par VobSub no tiene un índice, una paleta o datos de subtítulos válidos.")
    }

    private static func regularFileSize(_ url: URL) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize else { throw invalidIndex }
        return Int64(size)
    }

    private static func fields(_ line: String, pattern: NSRegularExpression) -> [String]? {
        guard let match = pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        return (1..<match.numberOfRanges).compactMap {
            Range(match.range(at: $0), in: line).map { String(line[$0]) }
        }
    }
}
