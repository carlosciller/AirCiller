import Foundation

@main
struct SubtitleOCRTextNormalizerSmokeTest {
    static func main() throws {
        let wrappedSong = SubtitleOCRTextNormalizer.normalize("& Lyrics s")
        let multilineSong = SubtitleOCRTextNormalizer.normalize(
            "& Only echoes passing\nthrough the night s"
        )
        let genuineAmpersand = SubtitleOCRTextNormalizer.normalize("Rock & Roll")
        let plural = SubtitleOCRTextNormalizer.normalize("Words disappear")
        let incompletePair = SubtitleOCRTextNormalizer.normalize("& Terms")

        guard wrappedSong == "♪ Lyrics ♪",
            multilineSong == "♪ Only echoes passing\nthrough the night ♪",
            genuineAmpersand == "Rock & Roll",
            plural == "Words disappear",
            incompletePair == "& Terms"
        else {
            throw NSError(domain: "SubtitleOCRTextNormalizerSmokeTest", code: 1)
        }
        print("Paired OCR music-note correction without broad text replacement: OK")
    }
}
