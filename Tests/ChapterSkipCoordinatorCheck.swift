import Foundation

enum ChapterSkipCoordinatorCheck {
    @MainActor static func run() {
        let coordinator = StreamCoordinator(libraryRecovery: nil)
        defer { coordinator.stop() }
        coordinator.beginSyntheticPlaybackSessionForChecks()
        coordinator.duration = 100
        coordinator.currentTime = 6
        coordinator.chapters = [
            MediaChapter(id: 0, start: 0, end: 5, title: "Cold open"),
            MediaChapter(id: 1, start: 5, end: 20, title: "Intro"),
            MediaChapter(id: 2, start: 20, end: 40, title: "Recap"),
            MediaChapter(id: 3, start: 40, end: 100, title: "Story"),
        ]
        precondition(coordinator.currentChapterSkip?.kind == .introduction)
        coordinator.showConversionAlert = true
        precondition(coordinator.currentChapterSkip == nil && !coordinator.skipMarkedChapter())
        precondition(coordinator.currentTime == 6)
        coordinator.showConversionAlert = false
        precondition(coordinator.skipMarkedChapter() && coordinator.currentTime == 20)
        precondition(coordinator.currentChapterSkip?.kind == .recap)
        precondition(coordinator.skipMarkedChapter() && coordinator.currentTime == 40)
        precondition(
            !coordinator.skipMarkedChapter() && coordinator.currentTime == 40,
            "An old marker cannot be reused outside its interval")
        coordinator.currentTime = 6
        coordinator.chapters[1] = MediaChapter(id: 1, start: 5, end: 20, title: "Chapter 2")
        precondition(coordinator.currentChapterSkip == nil && !coordinator.skipMarkedChapter())
        coordinator.stop()
        precondition(coordinator.currentChapterSkip == nil && !coordinator.skipMarkedChapter())
        // Source-to-presentation translation is the same existing map used by
        // ordinary chapter seeking; its dedicated timeline suite covers bounds.
        let adjusted = MoviePlaybackTimeline(sourceDuration: 100, presentationDuration: 103, videoContentOffset: 3)
        precondition(adjusted.presentationPosition(forSource: 20) == 23)
        print(
            "Chapter skip coordinator: explicit endpoints, pending decisions, stale markers and stopped sessions: OK (local only)"
        )
    }
}
