import Foundation

@main
struct TrackSettingsSmokeTest {
    static func main() {
        let original = TrackSettings(audioID: "audio-1", subtitleID: "subtitle-1")
        precondition(!original.canApply(replacing: original, current: original, sameMedia: true, controlsEnabled: true))
        var draft = original
        draft.subtitleID = nil
        precondition(draft.canApply(replacing: original, current: original, sameMedia: true, controlsEnabled: true))
        precondition(!draft.canApply(replacing: original, current: original, sameMedia: false, controlsEnabled: true))
        precondition(!draft.canApply(replacing: original, current: original, sameMedia: true, controlsEnabled: false))
        var current = original
        current.audioID = "audio-2"
        precondition(!draft.canApply(replacing: original, current: current, sameMedia: true, controlsEnabled: true))
        draft = original
        draft.audioDelay = 0.05
        precondition(draft.canApply(replacing: original, current: original, sameMedia: true, controlsEnabled: true))
        draft.audioDelay = 0
        precondition(!draft.canApply(replacing: original, current: original, sameMedia: true, controlsEnabled: true))
        draft.audioOutputMode = .stereo
        precondition(draft.canApply(replacing: original, current: original, sameMedia: true, controlsEnabled: true))
        precondition(!draft.hasKnownAudioTimingLimitation(isHDR: false, hasSelectedAudio: true))
        for delay in [-5.0, -0.05, 0.05, 5.0] {
            draft.audioDelay = delay
            precondition(draft.hasKnownAudioTimingLimitation(isHDR: false, hasSelectedAudio: true))
            precondition(!draft.hasKnownAudioTimingLimitation(isHDR: true, hasSelectedAudio: true))
            precondition(!draft.hasKnownAudioTimingLimitation(isHDR: nil, hasSelectedAudio: true))
            precondition(!draft.hasKnownAudioTimingLimitation(isHDR: false, hasSelectedAudio: false))
        }
        draft.audioDelay = .nan
        precondition(!draft.hasKnownAudioTimingLimitation(isHDR: false, hasSelectedAudio: true))
        print("Track settings: unchanged, edited, reverted, stale and busy drafts passed")
    }
}
