import Foundation

@main
struct MoviePlaybackTimelineSmokeTest {
    static func main() throws {
        let advance = MoviePlaybackTimeline(sourceDuration: 60, presentationDuration: 65, videoContentOffset: 5)
        let delay = MoviePlaybackTimeline(sourceDuration: 60, presentationDuration: 65, videoContentOffset: 0)
        try expect(advance.sourcePosition(forPresentation: 3) == 0, "Opening hold is source zero")
        try expect(advance.sourcePosition(forPresentation: 20) == 15, "Save movie time, not padded time")
        try expect(advance.presentationPosition(forSource: 15) == 20, "Resume the same movie frame")
        try expect(advance.presentationPosition(forSource: 0) == 0, "A fresh start keeps all leading audio")
        try expect(advance.sourcePosition(forPresentation: 65) == 60, "Natural end saves original duration")
        try expect(delay.sourcePosition(forPresentation: 64) == 60, "Trailing audio does not extend movie progress")
        try expect(delay.presentationPosition(forSource: 15) == 15, "Delayed audio does not move video")
        try expect(advance.sourcePosition(forPresentation: .nan) == 0, "Nonfinite input rejected")
        try expect(advance.presentationPosition(forSource: -.infinity) == 0, "Nonfinite restart rejected")
        for position in [1.0, 5, 15, 30, 59] {
            let movie = advance.sourcePosition(forPresentation: advance.presentationPosition(forSource: position))
            try expect(movie == position, "Round-trip source position")
        }
        print("Adjusted HLS: source history, receiver clock, chapter mapping and complete opening: OK")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "MoviePlaybackTimeline.\(message)", code: 1) }
    }
}
