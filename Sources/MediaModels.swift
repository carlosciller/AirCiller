import Foundation

struct AudioTrack: Identifiable, Hashable, Sendable {
    let streamIndex: Int
    let codec: String
    let profile: String?
    let channels: Int?
    let channelLayout: String?
    let language: String?
    let title: String?
    let isDefault: Bool

    var id: String { "audio-\(streamIndex)" }

    var isAtmos: Bool {
        profile?.localizedCaseInsensitiveContains("Atmos") == true
            || title?.localizedCaseInsensitiveContains("Atmos") == true
    }

    var canPassThrough: Bool {
        ["aac", "ac3", "eac3", "alac"].contains(codec.lowercased())
    }

    var displayName: String {
        TrackNames.combined(original: originalName, interpreted: interpretedName)
    }

    var originalName: String {
        TrackNames.original(
            language: language,
            title: title,
            fallback: "Pista \(streamIndex)"
        )
    }

    var interpretedName: String {
        guard let language = TrackNames.cleaned(language) else { return "Audio" }
        return LanguageNames.name(for: language)
    }

    var technicalDescription: String {
        var parts = [codecDisplayName]
        if isAtmos {
            parts.append("Atmos")
        } else if let channelDescription {
            parts.append(channelDescription)
        }
        return parts.joined(separator: " · ")
    }

    var codecDisplayName: String {
        switch codec.lowercased() {
        case "eac3": return "E-AC-3"
        case "ac3": return "AC-3"
        case "truehd": return "Dolby TrueHD"
        case "dts": return "DTS"
        case "aac": return "AAC"
        case "alac": return "ALAC"
        case "flac": return "FLAC"
        default: return codec.uppercased()
        }
    }

    var channelDescription: String? {
        switch channels {
        case 1: return "Mono"
        case 2: return "Estéreo"
        case 6: return "5.1"
        case 8: return "7.1"
        case .some(let channels): return "\(channels) canales"
        case nil: return nil
        }
    }
}

struct SubtitleTrack: Identifiable, Hashable, Sendable {
    let streamIndex: Int?
    let codec: String
    let language: String?
    let title: String?
    let isDefault: Bool
    let isForced: Bool
    let isHearingImpaired: Bool
    let externalPath: String?

    var id: String {
        if let externalPath { return "external-\(externalPath)" }
        return "subtitle-\(streamIndex ?? -1)"
    }

    var isTextBased: Bool {
        ["subrip", "srt", "ass", "ssa", "webvtt", "mov_text"].contains(codec.lowercased())
    }

    var usesAdvancedTextStyling: Bool {
        ["ass", "ssa"].contains(codec.lowercased())
    }

    var usesBitmapOCR: Bool {
        codec.lowercased() == "hdmv_pgs_subtitle"
    }

    var isSelectable: Bool {
        isTextBased || usesBitmapOCR
    }

    var stylingNotice: String? {
        if usesBitmapOCR {
            return
                "PGS de Blu-ray: AirCiller extrae solo esta pista, usa Apple Vision localmente y crea WebVTT seleccionable. Conserva tiempos y posición aproximada; no quema el texto ni modifica la película."
        }
        if usesAdvancedTextStyling {
            return
                "En WebVTT, AirCiller conserva posición, alineación y formato básico. En MP4 HDR y con karaoke, movimiento, rotación o dibujos ASS, el estilo se simplifica."
        }
        return nil
    }

    var isDescribedAsForced: Bool {
        isForced || title?.localizedCaseInsensitiveContains("forced") == true
            || title?.localizedCaseInsensitiveContains("forzad") == true
    }

    var isDescribedAsSDH: Bool {
        isHearingImpaired || title?.localizedCaseInsensitiveContains("SDH") == true
            || title?.localizedCaseInsensitiveContains("hearing impaired") == true
    }

    var displayName: String {
        TrackNames.combined(original: originalName, interpreted: interpretedName)
    }

    var originalName: String {
        if let externalPath {
            return URL(fileURLWithPath: externalPath).deletingPathExtension().lastPathComponent
        }
        return TrackNames.original(
            language: language,
            title: title,
            fallback: "Pista \(streamIndex ?? 0)"
        )
    }

    var interpretedName: String {
        let base = TrackNames.cleaned(language).map(LanguageNames.name(for:)) ?? "Subtítulos"
        var qualifiers: [String] = []
        if externalPath != nil {
            qualifiers.append("externos")
        }
        if isDescribedAsForced {
            qualifiers.append("forzados")
        }
        if isDescribedAsSDH {
            qualifiers.append("SDH")
        }
        return ([base] + qualifiers).joined(separator: " ")
    }

    var unsupportedReason: String? {
        guard !isSelectable else { return nil }
        switch codec.lowercased() {
        case "dvd_subtitle":
            return
                "Es una pista gráfica VobSub de DVD. Necesita un decodificador distinto al PGS de Blu-ray y todavía no se convierte."
        default:
            return "Apple TV no admite esta clase de subtítulo (\(codec)) como pista HLS nativa."
        }
    }
}

struct MediaChapter: Identifiable, Hashable, Sendable {
    let id: Int
    let start: Double
    let end: Double
    let title: String
}

enum AudioOutputMode: String, CaseIterable, Identifiable {
    case original
    case compatible
    case stereo

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .compatible: return "Compatible 5.1"
        case .stereo: return "Estéreo"
        }
    }

    var explanation: String {
        switch self {
        case .original: return "Sin recodificar"
        case .compatible: return "Convierte expresamente a E-AC-3"
        case .stereo: return "Convierte expresamente a AAC estéreo"
        }
    }
}

struct MediaProbe: Sendable {
    let duration: Double
    let fileSize: Int64?
    let bitRate: Int64?
    let videoStreamIndex: Int
    let videoCodec: String
    let videoProfile: String?
    let videoLevel: Int?
    let hevcCodecIdentifier: String?
    let width: Int?
    let height: Int?
    let frameRate: String?
    let colorTransfer: String?
    let isDolbyVision: Bool
    let dolbyVisionProfile: Int?
    let dolbyVisionLevel: Int?
    let dolbyVisionCompatibilityID: Int?
    let audioTracks: [AudioTrack]
    let subtitleTracks: [SubtitleTrack]
    let chapters: [MediaChapter]

    var isHDR: Bool {
        isDolbyVision || ["smpte2084", "arib-std-b67"].contains(colorTransfer?.lowercased() ?? "")
    }

    var displayDescription: String {
        var parts: [String] = []
        if let width, let height { parts.append("\(width)×\(height)") }
        parts.append(videoCodec.uppercased())
        if isDolbyVision {
            parts.append(dolbyVisionProfile.map { "Dolby Vision P\($0)" } ?? "Dolby Vision")
        } else if isHDR {
            parts.append("HDR")
        } else if let videoProfile {
            parts.append(videoProfile)
        }
        parts.append(TimeFormatting.duration(duration))
        return parts.joined(separator: " · ")
    }
}

struct MediaBadge: Identifiable, Hashable {
    let id: String
    let label: String
    let value: String
    let detail: String
}

enum MediaPresentation {
    static func resolutionLabel(width: Int?, height: Int?) -> String {
        let width = width ?? 0
        let height = height ?? 0
        if width >= 3_400 || height >= 1_900 { return "4K" }
        if width >= 2_500 || height >= 1_400 { return "1440p" }
        if width >= 1_850 || height >= 1_000 { return "Full HD" }
        if height > 0 { return "\(height)p" }
        return "Sin datos"
    }

    static func dolbyVisionProfile(_ profile: Int?, compatibilityID: Int?) -> String {
        if let profile, let compatibilityID { return "Perfil \(profile).\(compatibilityID)" }
        if let profile { return "Perfil \(profile)" }
        return "Perfil no indicado"
    }
}

struct RecentMediaItem: Codable, Identifiable, Hashable {
    var id: String { path }
    let path: String
    var title: String
    var lastOpened: Date
    var lastPosition: Double
    var duration: Double

    var url: URL { URL(fileURLWithPath: path) }
    var progress: Double { duration > 0 ? min(max(lastPosition / duration, 0), 1) : 0 }
}

struct QueueMediaItem: Codable, Identifiable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let title: String
    var url: URL { URL(fileURLWithPath: path) }
}

enum QueueOrdering {
    static func moving(
        _ items: [QueueMediaItem],
        fromOffsets: IndexSet,
        toOffset: Int
    ) -> [QueueMediaItem] {
        let validOffsets = fromOffsets.filter(items.indices.contains).sorted()
        guard !validOffsets.isEmpty else { return items }

        var reordered = items
        let moving = validOffsets.map { items[$0] }
        let removedBeforeDestination = validOffsets.filter { $0 < toOffset }.count
        for index in validOffsets.reversed() {
            reordered.remove(at: index)
        }
        let destination = min(max(0, toOffset - removedBeforeDestination), reordered.count)
        reordered.insert(contentsOf: moving, at: destination)
        return reordered
    }
}

enum TimeFormatting {
    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "--:--" }
        let total = Int(seconds.rounded(.down))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remaining = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remaining)
        }
        return String(format: "%02d:%02d", minutes, remaining)
    }
}

enum LanguageNames {
    private static let explicit: [String: String] = [
        "eng": "Inglés", "spa": "Español", "es": "Español", "fre": "Francés", "fra": "Francés",
        "ger": "Alemán", "deu": "Alemán", "ita": "Italiano", "por": "Portugués", "cat": "Catalán",
        "jpn": "Japonés", "kor": "Coreano", "chi": "Chino", "zho": "Chino", "rus": "Ruso",
        "dut": "Neerlandés", "nld": "Neerlandés", "pol": "Polaco", "tur": "Turco", "und": "Sin idioma",
    ]

    static func name(for code: String) -> String {
        let lower = code.lowercased().replacingOccurrences(of: "_", with: "-")
        let base = lower.split(separator: "-").first.map(String.init) ?? lower
        if let explicit = explicit[lower] ?? explicit[base] { return explicit }
        return Locale(identifier: "es_ES").localizedString(forLanguageCode: base)?.capitalized ?? code.uppercased()
    }

    static func originalName(for code: String) -> String {
        let lower = code.lowercased().replacingOccurrences(of: "_", with: "-")
        let base = lower.split(separator: "-").first.map(String.init) ?? lower
        return Locale(identifier: "en_US").localizedString(forLanguageCode: base)?.capitalized ?? code.uppercased()
    }

    static let subtitlePreferenceOptions: [LanguageOption] = [
        LanguageOption(code: "spa", name: "Español"),
        LanguageOption(code: "eng", name: "Inglés"),
        LanguageOption(code: "cat", name: "Catalán"),
        LanguageOption(code: "fra", name: "Francés"),
        LanguageOption(code: "deu", name: "Alemán"),
        LanguageOption(code: "ita", name: "Italiano"),
        LanguageOption(code: "por", name: "Portugués"),
        LanguageOption(code: "jpn", name: "Japonés"),
        LanguageOption(code: "kor", name: "Coreano"),
    ]

    static func matches(preferred: String, language: String?, title: String?) -> Bool {
        guard let preferredCode = canonical(preferred) else { return false }
        if canonical(language) == preferredCode { return true }
        guard
            let title = TrackNames.cleaned(title)?.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            ).lowercased()
        else { return false }
        return aliases[preferredCode, default: []].contains { alias in
            title.range(of: "\\b\(NSRegularExpression.escapedPattern(for: alias))\\b", options: .regularExpression)
                != nil
        }
    }

    private static let canonicalCodes: [String: String] = [
        "es": "spa", "spa": "spa", "eng": "eng", "en": "eng",
        "ca": "cat", "cat": "cat", "fr": "fra", "fre": "fra", "fra": "fra",
        "de": "deu", "ger": "deu", "deu": "deu", "it": "ita", "ita": "ita",
        "pt": "por", "por": "por", "ja": "jpn", "jpn": "jpn",
        "ko": "kor", "kor": "kor", "nl": "nld", "dut": "nld", "nld": "nld",
        "pl": "pol", "pol": "pol", "tr": "tur", "tur": "tur",
        "ru": "rus", "rus": "rus", "zh": "zho", "chi": "zho", "zho": "zho",
    ]

    private static let aliases: [String: [String]] = [
        "spa": ["spanish", "espanol", "castellano", "spa"],
        "eng": ["english", "ingles", "eng"],
        "cat": ["catalan", "catala", "cat"],
        "fra": ["french", "francais", "frances", "fra", "fre"],
        "deu": ["german", "deutsch", "aleman", "deu", "ger"],
        "ita": ["italian", "italiano", "ita"],
        "por": ["portuguese", "portugues", "por"],
        "jpn": ["japanese", "japones", "jpn"],
        "kor": ["korean", "coreano", "kor"],
    ]

    private static func canonical(_ code: String?) -> String? {
        guard let code = TrackNames.cleaned(code) else { return nil }
        let normalized = code.lowercased().replacingOccurrences(of: "_", with: "-")
        let base = normalized.split(separator: "-").first.map(String.init) ?? normalized
        return canonicalCodes[normalized] ?? canonicalCodes[base]
    }
}

struct LanguageOption: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    var id: String { code }
}

enum SubtitleTrackSelection {
    static func preferredTrack(in tracks: [SubtitleTrack], language: String) -> SubtitleTrack? {
        tracks
            .filter {
                $0.isSelectable
                    && LanguageNames.matches(
                        preferred: language,
                        language: $0.language,
                        title: $0.title
                    )
            }
            .sorted(by: isPreferred)
            .first
    }

    private static func isPreferred(_ left: SubtitleTrack, _ right: SubtitleTrack) -> Bool {
        if left.isTextBased != right.isTextBased {
            return left.isTextBased
        }
        if left.isDescribedAsForced != right.isDescribedAsForced {
            return !left.isDescribedAsForced
        }
        if left.isDescribedAsSDH != right.isDescribedAsSDH {
            return !left.isDescribedAsSDH
        }
        if left.isDefault != right.isDefault {
            return left.isDefault
        }
        if (left.externalPath == nil) != (right.externalPath == nil) {
            return left.externalPath == nil
        }
        return (left.streamIndex ?? Int.max) < (right.streamIndex ?? Int.max)
    }
}

private enum TrackNames {
    static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }

    static func combined(original: String, interpreted: String) -> String {
        let normalizedOriginal = normalized(original)
        let normalizedInterpreted = normalized(interpreted)
        if normalizedOriginal == normalizedInterpreted
            || normalizedOriginal.contains(normalizedInterpreted) && !normalizedInterpreted.isEmpty
        {
            return original
        }
        return "\(original) — \(interpreted)"
    }

    static func original(language: String?, title: String?, fallback: String) -> String {
        let cleanedLanguage = cleaned(language)
        if let title = cleaned(title) {
            guard let cleanedLanguage,
                cleanedLanguage.lowercased() != "und",
                !LanguageNames.matches(
                    preferred: cleanedLanguage,
                    language: nil,
                    title: title
                )
            else { return title }
            return "\(LanguageNames.originalName(for: cleanedLanguage)) \(title)"
        }
        if let cleanedLanguage, cleanedLanguage.lowercased() != "und" {
            return LanguageNames.originalName(for: cleanedLanguage)
        }
        return fallback
    }

    private static func normalized(_ value: String) -> String {
        value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .lowercased()
        .replacingOccurrences(of: "[^a-z0-9]+", with: "", options: .regularExpression)
    }
}
