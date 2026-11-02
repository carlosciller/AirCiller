import Foundation

enum PreparedPlaybackInformationCheck {
    @MainActor static func run() {
        let source = AudioTrack(
            streamIndex: 1, codec: "truehd", profile: "Atmos", channels: 8,
            channelLayout: "7.1", language: "eng", title: "Atmos", isDefault: true)
        let original = PreparedPlaybackInformation(
            route: .directMP4, audio: source, outputMode: .original, subtitle: nil)
        precondition(original.audio.contains("Atmos"))
        for mode in [AudioOutputMode.compatible, .stereo, .losslessFLAC] {
            let converted = PreparedPlaybackInformation(route: .hls, audio: source, outputMode: mode, subtitle: nil)
            precondition(converted.audio != original.audio)
            precondition(!converted.audio.contains("7.1"), "Never inherit source channels into a converted output")
            if mode != .losslessFLAC { precondition(!converted.audio.contains("Atmos")) }
        }
        let silent = PreparedPlaybackInformation(route: .hls, audio: nil, outputMode: .compatible, subtitle: nil)
        precondition(silent.audio == L10n.text("Sin audio"))
        let coordinator = StreamCoordinator(libraryRecovery: nil)
        precondition(coordinator.preparedPlaybackInformation == nil)
        coordinator.beginSyntheticPlaybackSessionForChecks(preparedInformation: original)
        coordinator.audioOutputMode = .stereo
        precondition(
            coordinator.preparedPlaybackInformation == original, "A selected plan is not a new completed preparation")
        coordinator.stop()
        precondition(coordinator.preparedPlaybackInformation == nil)
        print("Prepared information: source/converted labels, no inherited channels/Atmos and empty session: OK")
    }
}
