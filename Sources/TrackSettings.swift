import Foundation

/// A value copy edited by the track popover and committed only on Apply.
struct TrackSettings: Equatable {
    var audioID: String?
    var subtitleID: String?
    var audioDelay: Double = 0
    var subtitleDelay: Double = 0
    var audioOutputMode: AudioOutputMode = .original

    /// The known limitation is confined to SDR's separate HLS renditions.
    /// An unknown probe result must not be presented as a diagnosed timing fault.
    func hasKnownAudioTimingLimitation(isHDR: Bool?, hasSelectedAudio: Bool) -> Bool {
        isHDR == false && hasSelectedAudio && audioDelay.isFinite && abs(audioDelay) >= 0.001
    }

    /// An unchanged or stale inspector must never restart playback or overwrite
    /// settings applied elsewhere after the inspector was opened.
    func canApply(
        replacing original: Self,
        current: Self,
        sameMedia: Bool,
        controlsEnabled: Bool
    ) -> Bool {
        sameMedia && controlsEnabled && current == original && self != original
    }
}
