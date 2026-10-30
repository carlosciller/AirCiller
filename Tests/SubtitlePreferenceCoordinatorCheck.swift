import Foundation

enum SubtitlePreferenceCoordinatorCheck {
    @MainActor static func run() throws {
        // Called only inside the fresh UUID-suffixed coordinator-test preferences domain.
        let defaults = UserDefaults.standard
        let keys = ["preferredSubtitleLanguage", "fallbackSubtitleLanguage", "preferredSubtitleKind"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw NSError(domain: "SubtitlePreferences.\(message)", code: 1) }
        }
        let track = SubtitleTrack(
            streamIndex: 2, codec: "subrip", language: "eng", title: "English",
            isDefault: true, isForced: false, isHearingImpaired: false, externalPath: nil)
        let coordinator = StreamCoordinator()
        try require(coordinator.fallbackSubtitleLanguage.isEmpty, "existing installations have no fallback")
        coordinator.setPreferredSubtitleLanguage("spa")
        try require(coordinator.automaticSubtitleTrack(in: [track]) == nil, "baseline missing primary")
        coordinator.setFallbackSubtitleLanguage("eng")
        try require(coordinator.automaticSubtitleTrack(in: [track]) == track, "production automatic selection")
        let reloaded = StreamCoordinator()
        try require(
            reloaded.fallbackSubtitleLanguage == "eng"
                && reloaded.automaticSubtitleTrack(in: [track]) == track, "persisted alternative")
        coordinator.selectedSubtitleID = "manually-selected-track"
        coordinator.beginSyntheticPlaybackSessionForChecks()
        coordinator.setFallbackSubtitleLanguage("fra")
        coordinator.setPreferredSubtitleLanguage("jpn")
        coordinator.setPreferredSubtitleKind(.sdh)
        try require(
            coordinator.selectedSubtitleID == "manually-selected-track" && coordinator.isStreaming,
            "settings never mutate the active track or playback")
        coordinator.setPreferredSubtitleLanguage("")
        coordinator.setFallbackSubtitleLanguage("eng")
        try require(coordinator.automaticSubtitleTrack(in: [track]) == nil, "off remains off")
        coordinator.setPreferredSubtitleLanguage("spa")
        coordinator.setRemoteLanguagePreferences(audio: "", subtitles: "jpn", persistent: false)
        try require(
            coordinator.automaticSubtitleTrack(in: [track]) == nil,
            "explicit remote session does not inherit saved alternative")
        coordinator.stop()
        try require(
            coordinator.automaticSubtitleTrack(in: [track]) == track,
            "saved preference returns after session scope ends")
        print("Subtitle preferences: production selection, persistence, active/manual selection and remote scope: OK")
    }
}
