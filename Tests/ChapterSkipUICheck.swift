import AppKit
import SwiftUI

@main
struct ChapterSkipUICheck: App {
    @NSApplicationDelegateAdaptor(AirCillerAppDelegate.self) private var appDelegate
    private let coordinator: StreamCoordinator

    init() {
        guard Bundle.main.bundleIdentifier?.hasPrefix("local.airciller.ChapterSkipCheck.") == true,
            CommandLine.arguments.contains("--skip-device-scan")
        else { fatalError("Isolated chapter UI check required") }
        HistoryStore.saveQueue([])
        HistoryStore.saveRecent([])
        HistoryStore.saveSeasons([])
        coordinator = StreamCoordinator(libraryRecovery: nil)
        coordinator.beginSyntheticPlaybackSessionForChecks()
        coordinator.isPlaying = false
        coordinator.duration = 100
        coordinator.currentTime = 6
        coordinator.chapters = [
            MediaChapter(id: 0, start: 0, end: 20, title: "Intro"),
            MediaChapter(id: 1, start: 20, end: 40, title: "Recap"),
            MediaChapter(id: 2, start: 40, end: 100, title: "Chapter 3"),
        ]
    }

    var body: some Scene {
        Window("AirCiller Chapter Check", id: "main") {
            ContentView(coordinator: coordinator, appDelegate: appDelegate)
                .frame(minWidth: 720, minHeight: 520)
                .preferredColorScheme(CommandLine.arguments.contains("--light") ? .light : .dark)
        }
        .defaultSize(width: 720, height: 520)
    }
}
