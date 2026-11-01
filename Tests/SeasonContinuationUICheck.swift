import AppKit
import SwiftUI

/// Real production view, isolated synthetic preferences, deliberately unavailable
/// media. Native continuation can exercise recovery without opening any receiver.
@main
struct SeasonContinuationUICheck: App {
    @NSApplicationDelegateAdaptor(AirCillerAppDelegate.self) private var appDelegate
    private let coordinator: StreamCoordinator

    init() {
        guard let domain = Bundle.main.bundleIdentifier,
            domain.hasPrefix("local.airciller.SeasonContinuationCheck."),
            CommandLine.arguments.contains("--skip-device-scan")
        else { fatalError("Isolated UI check required") }
        let first = SeasonFolder(path: "/synthetic-continuation/one", title: "Season One", isExpanded: true)
        let completed = SeasonFolder(path: "/synthetic-continuation/two", title: "Completed Season", isExpanded: false)
        HistoryStore.saveSeasons([first, completed])
        HistoryStore.saveRecent([])
        HistoryStore.saveQueue([
            QueueMediaItem(
                path: first.path + "/Episode 10.mkv", title: "Episode 10", seasonID: first.id, lastPosition: 900,
                duration: 900, watched: true),
            QueueMediaItem(
                path: first.path + "/Episode 2.mkv",
                title: "Example.Show.S01E02.A.Very.Long.Original.Episode.Name.1080p.BluRay.mkv", seasonID: first.id,
                lastPosition: 42, duration: 900),
            QueueMediaItem(
                path: completed.path + "/Episode 1.mkv", title: "Episode 1", seasonID: completed.id, watched: true),
        ])
        coordinator = StreamCoordinator(libraryRecovery: nil)
        coordinator.focusQueueSeason(first.id)
    }

    var body: some Scene {
        Window("AirCiller Season Check", id: "main") {
            ContentView(coordinator: coordinator, appDelegate: appDelegate)
                .frame(minWidth: 720, minHeight: 520)
                .preferredColorScheme(CommandLine.arguments.contains("--light") ? .light : .dark)
        }
        .defaultSize(
            width: CommandLine.arguments.contains("--narrow") ? 720 : 960,
            height: CommandLine.arguments.contains("--narrow") ? 520 : 650)
    }
}
