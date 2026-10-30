import Foundation

@main
struct SubtitleFallbackSmokeTest {
    static func main() throws {
        func track(
            _ index: Int, _ language: String, codec: String = "subrip",
            title: String? = nil, forced: Bool = false, sdh: Bool = false
        ) -> SubtitleTrack {
            SubtitleTrack(
                streamIndex: index, codec: codec, language: language, title: title,
                isDefault: false, isForced: forced, isHearingImpaired: sdh, externalPath: nil)
        }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "SubtitleFallback.\(message)", code: 1) }
        }
        let english = track(1, "eng", title: "English original title")
        let spanish = track(2, "spa")
        let french = track(3, "fra")
        let englishSDH = track(4, "eng", sdh: true)
        let englishForced = track(5, "eng", forced: true)
        let spanishForced = track(6, "spa", forced: true)
        let unsupportedSpanish = track(7, "spa", codec: "dvb_subtitle")
        let spanishPGS = track(8, "spa", codec: "hdmv_pgs_subtitle")
        let all = [english, englishSDH, englishForced, french]
        try require(
            SubtitleTrackSelection.preferredTrack(in: all, language: "spa") == nil,
            "legacy primary-only selection remains off when missing")
        for preference in SubtitleTrackPreference.allCases {
            let expected = preference == .forced ? englishForced : preference == .sdh ? englishSDH : english
            try require(
                SubtitleTrackSelection.preferredTrack(
                    in: all, language: "spa",
                    preference: preference, fallbackLanguage: "en-US") == expected, "fallback respects type")
            try require(
                SubtitleTrackSelection.preferredTrack(
                    in: all, language: "",
                    preference: preference, fallbackLanguage: "eng") == nil, "off dominates fallback")
        }
        try require(
            SubtitleTrackSelection.preferredTrack(
                in: all + [spanish], language: "es",
                fallbackLanguage: "eng") == spanish, "primary wins")
        try require(
            SubtitleTrackSelection.preferredTrack(
                in: all + [spanishPGS], language: "spa",
                fallbackLanguage: "eng") == spanishPGS, "primary bitmap is not replaced by cheaper fallback")
        try require(
            SubtitleTrackSelection.preferredTrack(
                in: all + [unsupportedSpanish], language: "spa",
                fallbackLanguage: "eng") == english, "unsupported primary does not block fallback")
        try require(
            SubtitleTrackSelection.preferredTrack(
                in: [english, spanish], language: "spa",
                preference: .forced, fallbackLanguage: "eng") == nil, "forced never enables full subtitles")
        try require(
            SubtitleTrackSelection.preferredTrack(
                in: [spanish, englishForced], language: "spa",
                preference: .forced, fallbackLanguage: "eng") == englishForced, "missing eligible forced uses fallback")
        try require(
            SubtitleTrackSelection.preferredTrack(
                in: all + [spanishForced], language: "spa",
                preference: .forced, fallbackLanguage: "eng") == spanishForced, "primary forced wins")
        try require(
            SubtitleTrackSelection.preferredTrack(
                in: all, language: "jpn",
                fallbackLanguage: "spa") == nil, "neither language never selects unrelated track")
        try require(
            SubtitleTrackSelection.preferredTrack(
                in: all, language: "spa",
                fallbackLanguage: "invalid") == nil, "invalid fallback stays off")
        try require(
            SubtitleTrackSelection.preferredTrack(
                in: [], language: "spa",
                fallbackLanguage: "eng") == nil, "empty tracks")
        let byTitle = track(9, "und", title: "English")
        try require(
            SubtitleTrackSelection.preferredTrack(
                in: [byTitle], language: "spa",
                fallbackLanguage: "eng") == byTitle, "existing title matching retained")
        for language in ["spa", "eng", "fra", ""] {
            for preference in SubtitleTrackPreference.allCases {
                let previous = SubtitleTrackSelection.preferredTrack(
                    in: all, language: language, preference: preference)
                try require(
                    SubtitleTrackSelection.preferredTrack(
                        in: all, language: language,
                        preference: preference, fallbackLanguage: language) == previous, "same language is harmless")
                try require(
                    SubtitleTrackSelection.preferredTrack(
                        in: all, language: language,
                        preference: preference, fallbackLanguage: "") == previous, "unset fallback preserves defaults")
            }
        }
        try require(
            english.title == "English original title" && englishSDH.isHearingImpaired,
            "metadata unchanged")
        print("Subtitle fallback: ordered languages, eligibility, normal/SDH/forced, disabled and legacy policy: OK")
    }
}
