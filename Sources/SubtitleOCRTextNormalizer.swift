import Foundation

enum SubtitleOCRTextNormalizer {
    /// Vision can read the two eighth-note glyphs around song lyrics as
    /// `& ... s`. Only that paired, whitespace-delimited shape is corrected;
    /// normal ampersands and words ending in `s` remain untouched.
    static func normalize(_ value: String) -> String {
        guard value.hasPrefix("& "), value.hasSuffix(" s") else { return value }
        let start = value.index(value.startIndex, offsetBy: 2)
        let end = value.index(value.endIndex, offsetBy: -2)
        guard start < end else { return value }
        let interior = value[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        guard interior.contains(where: { $0.isLetter || $0.isNumber }) else { return value }
        return "♪ \(interior) ♪"
    }
}
