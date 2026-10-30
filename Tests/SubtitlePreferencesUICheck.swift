import SwiftUI

/// Production Settings view in a disposable bundle/domain, without media or receiver access.
@main
struct SubtitlePreferencesUICheck: App {
    private let coordinator: StreamCoordinator

    init() {
        guard let domain = Bundle.main.bundleIdentifier,
            domain.hasPrefix("local.airciller.SubtitlePreferencesCheck."),
            CommandLine.arguments.contains("--skip-device-scan")
        else { fatalError("Requires isolated preferences and --skip-device-scan") }
        if UserDefaults.standard.persistentDomain(forName: domain) == nil {
            UserDefaults.standard.set("spa", forKey: "preferredSubtitleLanguage")
        }
        coordinator = StreamCoordinator()
    }

    var body: some Scene {
        Window("AirCiller Subtitle Preferences Check", id: "main") {
            PlaybackSettingsView(coordinator: coordinator)
                .frame(width: 640, height: 500)
        }
        .windowResizability(.contentSize)
    }
}
