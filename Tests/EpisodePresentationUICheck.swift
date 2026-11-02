import AppKit
import SwiftUI

@main
struct EpisodePresentationUICheck: App {
    @NSApplicationDelegateAdaptor(AirCillerAppDelegate.self) private var appDelegate
    private let coordinator: StreamCoordinator

    init() {
        guard Bundle.main.bundleIdentifier?.hasPrefix("local.airciller.EpisodePresentationCheck.") == true,
            CommandLine.arguments.contains("--skip-device-scan")
        else { fatalError("Isolated episode check required") }
        let season = SeasonFolder(path: "/synthetic-names", title: "Example Show", isExpanded: true)
        if UserDefaults.standard.object(forKey: HistoryStore.queueKey) == nil {
            HistoryStore.saveSeasons([season])
            HistoryStore.saveRecent([])
            let filename = "Example.Show.S01E01.Let.You.Down.1080p.BluRay.Remux.DTS-HD.MA.5.1.mkv"
            HistoryStore.saveQueue([
                QueueMediaItem(
                    path: season.path + "/" + filename,
                    title: URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent,
                    seasonID: season.id, lastPosition: 42, duration: 900)
            ])
        }
        coordinator = StreamCoordinator(libraryRecovery: nil)
        coordinator.focusQueueSeason(season.id)
    }

    var body: some Scene {
        Window("AirCiller Episode Check", id: "main") {
            ContentView(coordinator: coordinator, appDelegate: appDelegate)
                .frame(minWidth: 720, minHeight: 520)
                .preferredColorScheme(CommandLine.arguments.contains("--light") ? .light : .dark)
        }
        .defaultSize(width: 960, height: 650)
    }
}
