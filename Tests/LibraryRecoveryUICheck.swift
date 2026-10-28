import AppKit
import SwiftUI

/// Opt-in native acceptance harness. Uses production views and coordinator,
/// an isolated bundle identifier and synthetic preferences. No receiver scan.
@main
struct LibraryRecoveryUICheck: App {
    @NSApplicationDelegateAdaptor(AirCillerAppDelegate.self) private var appDelegate
    private let coordinator: StreamCoordinator

    init() {
        guard let domain = Bundle.main.bundleIdentifier,
            domain.hasPrefix("local.airciller.RecoveryUICheck."),
            CommandLine.arguments.contains("--skip-device-scan")
        else { fatalError("Requires isolated bundle and --skip-device-scan") }
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(domain)
        let recovery = LibraryRecovery(defaults: .standard, archive: .init(directory: root))
        let fixtureFolder = root.appendingPathComponent("Import Fixtures/Season")
        try! FileManager.default.createDirectory(at: fixtureFolder, withIntermediateDirectories: true)
        for file in [
            fixtureFolder.appendingPathComponent("Episode 3.mkv"),
            fixtureFolder.deletingLastPathComponent().appendingPathComponent("Movie.mkv"),
        ] where !FileManager.default.fileExists(atPath: file.path) {
            try! Data("synthetic library admission fixture".utf8).write(to: file)
        }
        if UserDefaults.standard.persistentDomain(forName: domain) == nil {
            HistoryStore.saveQueue([
                QueueMediaItem(path: "/synthetic/Episode 1.mkv", title: "Episode 1", lastPosition: 120, duration: 900),
                QueueMediaItem(path: "/synthetic/Episode 2.mkv", title: "Episode 2"),
            ])
            HistoryStore.saveRecent([])
            HistoryStore.saveSeasons([])
            guard recovery.inspect().isEmpty else { fatalError("Could not create isolated recovery fixture") }
            UserDefaults.standard.set(Data("synthetic damaged data".utf8), forKey: HistoryStore.queueKey)
        }
        coordinator = StreamCoordinator(libraryRecovery: recovery)
    }

    var body: some Scene {
        Window("AirCiller Recovery Check", id: "main") {
            ContentView(coordinator: coordinator, appDelegate: appDelegate)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 960, height: 650)
    }
}
