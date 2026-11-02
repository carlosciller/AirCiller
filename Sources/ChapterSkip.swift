import Foundation

struct ChapterSkip: Equatable, Sendable {
    enum Kind: Sendable {
        case introduction, recap

        var actionTitle: String {
            switch self {
            case .introduction: "Saltar introducción"
            case .recap: "Saltar resumen"
            }
        }
    }

    let kind: Kind
    let chapter: MediaChapter

    static func current(at position: Double, chapters: [MediaChapter], duration: Double) -> Self? {
        guard position.isFinite, position >= 0, duration.isFinite, duration > 0 else { return nil }
        let containing = chapters.filter { valid($0, duration: duration) && $0.start <= position && position < $0.end }
        guard containing.count == 1, let chapter = containing.first,
            chapter.end - position >= 0.5, chapter.end <= duration - 0.5,
            let kind = kind(for: chapter.title)
        else { return nil }
        // Nested/overlapping editions do not establish one unambiguous interval.
        guard
            !chapters.contains(where: {
                $0 != chapter && $0.start < chapter.end && $0.end > chapter.start
            })
        else { return nil }
        return Self(kind: kind, chapter: chapter)
    }

    private static func valid(_ chapter: MediaChapter, duration: Double) -> Bool {
        chapter.start.isFinite && chapter.end.isFinite && chapter.start >= 0
            && chapter.end > chapter.start && chapter.end <= duration
    }

    private static func kind(for title: String) -> Kind? {
        var value = title.folding(
            options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")
        )
        .lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // A sequence prefix is metadata, not a timing inference.
        if let prefix = value.range(
            of: #"^(?:(?:chapter|capitulo)\s+)?[0-9]{1,3}\s*[-:.]\s*"#, options: .regularExpression)
        {
            value.removeSubrange(prefix)
        }
        switch value {
        case "intro", "introduction", "opening", "opening credits", "opening theme", "op", "op1", "op2", "op 1", "op 2",
            "introduccion", "cabecera", "apertura", "オープニング":
            return .introduction
        case "recap", "previously", "previously on", "resumen", "anteriormente", "en episodios anteriores",
            "recapitulacion", "前回のあらすじ":
            return .recap
        default:
            return nil
        }
    }
}
