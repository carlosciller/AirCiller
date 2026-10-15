import Foundation

/// A value copy edited by the track popover and committed only on Apply.
struct TrackSettings: Equatable {
    var audioID: String?
    var subtitleID: String?
    var audioDelay: Double = 0
    var subtitleDelay: Double = 0
    var audioOutputMode: AudioOutputMode = .original

    func hasSupportedAudioOutput(audio: AudioTrack?, isHDR: Bool?) -> Bool {
        guard audioOutputMode == .losslessFLAC else { return true }
        guard let isHDR else { return false }
        return audioOutputMode.isAvailable(audio: audio, isDirectMP4: isHDR && subtitleID != nil)
            && audioDelay.isFinite && abs(audioDelay) < 0.001
    }

    /// Adjusted SDR keeps every sample by extending the presentation interval.
    /// Unknown probe results must not be presented as an adjusted timeline.
    func hasAdjustedAudioTimeline(isHDR: Bool?, hasSelectedAudio: Bool) -> Bool {
        audioOutputMode != .losslessFLAC && isHDR == false && hasSelectedAudio
            && audioDelay.isFinite && abs(audioDelay) >= 0.001
    }

    var adjustedAudioTimelineExplanation: String {
        audioDelay < 0
            ? L10n.text(
                "Al adelantar el audio, el primer fotograma se mantiene brevemente para conservar todo el inicio. La duración del stream aumenta."
            )
            : L10n.text(
                "Al retrasar el audio, la reproducción continúa después del último fotograma hasta completar la pista. La duración del stream aumenta."
            )
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
