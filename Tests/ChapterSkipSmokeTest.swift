import Foundation

@main
struct ChapterSkipSmokeTest {
    static func main() {
        func chapter(_ name: String, _ start: Double = 0, _ end: Double = 20, _ id: Int = 0) -> MediaChapter {
            MediaChapter(id: id, start: start, end: end, title: name)
        }
        func marker(_ chapters: [MediaChapter], position: Double = 3, duration: Double = 100) -> ChapterSkip? {
            ChapterSkip.current(at: position, chapters: chapters, duration: duration)
        }
        for name in [
            "Intro", " INTRO ", "Opening", "Opening Credits", "OP", "OP2", "01 - Intro", "Capítulo 2: Introducción",
            "Cabecera", "オープニング",
        ] {
            precondition(marker([chapter(name)])?.kind == .introduction, name)
        }
        for name in ["Recap", "Previously On", "Resumen", "Anteriormente", "前回のあらすじ"] {
            precondition(marker([chapter(name)])?.kind == .recap, name)
        }
        for name in [
            "Chapter 1", "Capítulo 2", "Episode", "Introduction to the story", "Opening night", "Intro / Episode",
            "Ending", "Credits", "Recap + OP",
        ] {
            precondition(marker([chapter(name)]) == nil, name)
        }
        let intro = chapter("Intro", 5, 20)
        precondition(marker([intro], position: 4) == nil)
        precondition(marker([intro], position: 5)?.chapter.end == 20)
        precondition(marker([intro], position: 20) == nil)
        precondition(marker([intro], position: 19.75) == nil)
        precondition(marker([chapter("Intro", 0, 100)]) == nil, "Do not skip the whole file")
        for bad in [
            chapter("Intro", -1, 20), chapter("Intro", 10, 2), chapter("Intro", 0, 101), chapter("Intro", 0, .infinity),
        ] {
            precondition(marker([bad]) == nil)
        }
        precondition(marker([intro, chapter("Episode", 0, 100, 1)], position: 6) == nil)
        precondition(marker([intro, chapter("Corrupt parent", 0, 101, 1)], position: 6) == nil)
        precondition(marker([intro, intro], position: 6) == nil, "Duplicate editions are ambiguous")
        precondition(marker([intro, chapter("Scene", 18, 100, 1)], position: 6) == nil)
        precondition(
            marker([chapter("Cold open", 0, 5, 1), intro, chapter("Story", 20, 100, 2)], position: 6)?.chapter == intro)
        precondition(marker([], position: .nan) == nil && marker([intro], duration: .infinity) == nil)
        precondition(
            marker([chapter("Recap", 0, 600)], duration: 1200)?.chapter.end == 600,
            "Never replace explicit boundaries with an assumed intro duration")
        print("Chapter skips: explicit labels/bounds, no guesses, overlap rejection and exact endpoint: OK")
    }
}
