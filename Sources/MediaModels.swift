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
            fallback: L10n.format("Pista %lld", Int64(streamIndex))
        )
    }

    var interpretedName: String {
        guard let language = TrackNames.cleaned(language) else { return L10n.text("Audio") }
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
        case 1: return L10n.text("Mono")
        case 2: return L10n.text("Estéreo")
        case 6: return "5.1"
        case 8: return "7.1"
        case .some(let channels): return L10n.format("%lld canales", Int64(channels))
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
        ["hdmv_pgs_subtitle", "dvd_subtitle"].contains(codec.lowercased())
    }

    var isSelectable: Bool {
        isTextBased || usesBitmapOCR
    }

    var stylingNotice: String? {
        if usesBitmapOCR {
            return L10n.text(
                "PGS/VobSub: AirCiller extrae solo esta pista, usa Apple Vision localmente y crea WebVTT seleccionable. Conserva tiempos y posición aproximada; no quema el texto ni modifica la película."
            )
        }
        if usesAdvancedTextStyling {
            return L10n.text(
                "En WebVTT, AirCiller conserva posición, alineación y formato básico. En MP4 HDR y con karaoke, movimiento, rotación o dibujos ASS, el estilo se simplifica."
            )
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
            fallback: L10n.format("Pista %lld", Int64(streamIndex ?? 0))
        )
    }

    var interpretedName: String {
        let base = TrackNames.cleaned(language).map(LanguageNames.name(for:)) ?? L10n.text("Subtítulos")
        var qualifiers: [String] = []
        if externalPath != nil {
            qualifiers.append(L10n.text("externos"))
        }
        if isDescribedAsForced {
            qualifiers.append(L10n.text("forzados"))
        }
        if isDescribedAsSDH {
            qualifiers.append("SDH")
        }
        return ([base] + qualifiers).joined(separator: " ")
    }

    var unsupportedReason: String? {
        guard !isSelectable else { return nil }
        return L10n.format(
            "Apple TV no admite esta clase de subtítulo (%@) como pista HLS nativa.", codec)
    }
}

enum SubtitleTrackPreference: String, CaseIterable, Identifiable, Sendable {
    case standard
    case sdh
    case forced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return L10n.text("Normales")
        case .sdh: return "SDH"
        case .forced: return L10n.text("Solo forzados")
        }
    }

    var explanation: String {
        switch self {
        case .standard:
            return L10n.text("Prefiere subtítulos normales y usa SDH si no hay otra pista del idioma elegido.")
        case .sdh:
            return L10n.text("Prefiere SDH y usa una pista normal si no hay SDH en el idioma elegido.")
        case .forced:
            return L10n.text("Activa únicamente una pista forzada. Si no existe, deja los subtítulos desactivados.")
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
        case .original: return L10n.text("Original")
        case .compatible: return L10n.text("Compatible 5.1")
        case .stereo: return L10n.text("Estéreo")
        }
    }

    var explanation: String {
        switch self {
        case .original: return L10n.text("Sin recodificar")
        case .compatible: return L10n.text("Convierte expresamente a E-AC-3")
        case .stereo: return L10n.text("Convierte expresamente a AAC estéreo")
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

struct VideoStreamCandidate: Equatable, Sendable {
    let index: Int
    let width: Int?
    let height: Int?
    let isDefault: Bool
    let isAttachedPicture: Bool
}

enum VideoStreamSelection {
    static func primaryStreamIndex(in candidates: [VideoStreamCandidate]) -> Int? {
        candidates
            .filter { !$0.isAttachedPicture }
            .sorted(by: isPreferred)
            .first?.index
    }

    private static func isPreferred(_ left: VideoStreamCandidate, _ right: VideoStreamCandidate) -> Bool {
        if left.isDefault != right.isDefault {
            return left.isDefault
        }
        let leftPixels = (left.width ?? 0) * (left.height ?? 0)
        let rightPixels = (right.width ?? 0) * (right.height ?? 0)
        if leftPixels != rightPixels {
            return leftPixels > rightPixels
        }
        return left.index < right.index
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
        return L10n.text("Sin datos")
    }

    static func dolbyVisionProfile(_ profile: Int?, compatibilityID: Int?) -> String {
        if let profile, let compatibilityID {
            return L10n.format("Perfil %lld.%lld", Int64(profile), Int64(compatibilityID))
        }
        if let profile { return L10n.format("Perfil %lld", Int64(profile)) }
        return L10n.text("Perfil no indicado")
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

    static func movingItem(
        _ items: [QueueMediaItem],
        id: String,
        by offset: Int
    ) -> [QueueMediaItem]? {
        guard offset != 0,
            let previousIndex = items.firstIndex(where: { $0.id == id })
        else {
            return nil
        }

        let currentIndex = min(max(previousIndex + offset, items.startIndex), items.index(before: items.endIndex))
        guard currentIndex != previousIndex else { return nil }

        var reordered = items
        let item = reordered.remove(at: previousIndex)
        reordered.insert(item, at: currentIndex)
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
    private static let languageCodes: [String: String] = [
        "eng": "en", "spa": "es", "es": "es", "fre": "fr", "fra": "fr",
        "ger": "de", "deu": "de", "ita": "it", "por": "pt", "cat": "ca",
        "jpn": "ja", "kor": "ko", "chi": "zh", "zho": "zh", "rus": "ru",
        "dut": "nl", "nld": "nl", "pol": "pl", "tur": "tr",
    ]

    static func name(for code: String) -> String {
        let lower = code.lowercased().replacingOccurrences(of: "_", with: "-")
        let base = lower.split(separator: "-").first.map(String.init) ?? lower
        if lower == "und" || base == "und" { return L10n.text("Sin idioma") }
        let resolved = languageCodes[lower] ?? languageCodes[base] ?? base
        return L10n.locale.localizedString(forLanguageCode: resolved)?.capitalized(with: L10n.locale)
            ?? code.uppercased()
    }

    static func originalName(for code: String) -> String {
        let lower = code.lowercased().replacingOccurrences(of: "_", with: "-")
        let base = lower.split(separator: "-").first.map(String.init) ?? lower
        return Locale(identifier: "en_US").localizedString(forLanguageCode: base)?.capitalized ?? code.uppercased()
    }

    static let subtitlePreferenceOptions: [LanguageOption] =
        ["spa", "eng", "cat", "fra", "deu", "ita", "por", "jpn", "kor"].map {
            LanguageOption(code: $0, name: name(for: $0))
        }

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
    static func preferredTrack(
        in tracks: [SubtitleTrack],
        language: String,
        preference: SubtitleTrackPreference = .standard
    ) -> SubtitleTrack? {
        let matching =
            tracks
            .filter {
                $0.isSelectable
                    && LanguageNames.matches(
                        preferred: language,
                        language: $0.language,
                        title: $0.title
                    )
            }
        let eligible =
            preference == .forced
            ? matching.filter(\.isDescribedAsForced)
            : matching
        return
            eligible
            .sorted { isPreferred($0, $1, preference: preference) }
            .first
    }

    private static func isPreferred(
        _ left: SubtitleTrack,
        _ right: SubtitleTrack,
        preference: SubtitleTrackPreference
    ) -> Bool {
        if left.isTextBased != right.isTextBased {
            return left.isTextBased
        }
        let leftRank = preferenceRank(for: left, preference: preference)
        let rightRank = preferenceRank(for: right, preference: preference)
        if leftRank != rightRank {
            return leftRank < rightRank
        }
        if left.isDefault != right.isDefault {
            return left.isDefault
        }
        if (left.externalPath == nil) != (right.externalPath == nil) {
            return left.externalPath == nil
        }
        return (left.streamIndex ?? Int.max) < (right.streamIndex ?? Int.max)
    }

    private static func preferenceRank(
        for track: SubtitleTrack,
        preference: SubtitleTrackPreference
    ) -> Int {
        if track.isDescribedAsForced { return preference == .forced ? 0 : 2 }
        switch preference {
        case .standard, .forced:
            return track.isDescribedAsSDH ? 1 : 0
        case .sdh:
            return track.isDescribedAsSDH ? 0 : 1
        }
    }
}

enum AudioTrackSelection {
    static func preferredTrack(in tracks: [AudioTrack], language: String) -> AudioTrack? {
        tracks
            .filter {
                LanguageNames.matches(
                    preferred: language,
                    language: $0.language,
                    title: $0.title
                )
            }
            .sorted(by: isPreferred)
            .first
    }

    private static func isPreferred(_ left: AudioTrack, _ right: AudioTrack) -> Bool {
        if left.isDefault != right.isDefault {
            return left.isDefault
        }
        return left.streamIndex < right.streamIndex
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
