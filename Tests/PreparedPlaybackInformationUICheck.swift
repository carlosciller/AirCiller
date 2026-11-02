import AppKit
import SwiftUI

@main
struct PreparedPlaybackInformationUICheck: App {
    private let coordinator: StreamCoordinator

    init() {
        guard Bundle.main.bundleIdentifier?.hasPrefix("local.airciller.PreparedPlaybackInformationCheck.") == true,
            CommandLine.arguments.contains("--skip-device-scan")
        else { fatalError("Isolated information check required") }
        coordinator = StreamCoordinator(libraryRecovery: nil)
        let source = AudioTrack(
            streamIndex: 1, codec: "truehd", profile: "Atmos", channels: 8,
            channelLayout: "7.1", language: "eng", title: "Atmos", isDefault: true)
        coordinator.audioTracks = [source]
        coordinator.selectedAudioID = source.id
        coordinator.audioOutputMode = .compatible
        coordinator.beginSyntheticPlaybackSessionForChecks(
            preparedInformation: PreparedPlaybackInformation(
                route: .hls, audio: source, outputMode: .compatible, subtitle: nil))
    }

    var body: some Scene {
        Window("AirCiller Information Check", id: "main") {
            PlaybackInformationView(coordinator: coordinator)
                .preferredColorScheme(CommandLine.arguments.contains("--light") ? .light : .dark)
        }
        .windowResizability(.contentSize)
    }
}
