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
        let pcm = AudioTrack(
            streamIndex: 1, codec: "pcm_s24le", profile: nil, channels: 2, channelLayout: "stereo",
            language: nil, title: nil, isDefault: true, sampleRate: 48_000, bitsPerSample: 24)
        draft.audioOutputMode = .losslessFLAC
        draft.audioDelay = 0
        draft.subtitleID = nil
        precondition(draft.hasSupportedAudioOutput(audio: pcm, isHDR: false))
        precondition(draft.hasSupportedAudioOutput(audio: pcm, isHDR: true))
        precondition(!draft.hasSupportedAudioOutput(audio: pcm, isHDR: nil))
        precondition(!draft.hasSupportedAudioOutput(audio: nil, isHDR: false))
        draft.subtitleID = "subtitle-1"
        precondition(!draft.hasSupportedAudioOutput(audio: pcm, isHDR: true))
        for delay in [-0.05, 0.05, Double.nan] {
            draft.audioDelay = delay
            precondition(!draft.hasSupportedAudioOutput(audio: pcm, isHDR: false))
            precondition(!draft.hasKnownAudioTimingLimitation(isHDR: false, hasSelectedAudio: true))
        }
        print("Track settings: unchanged, edited, reverted, stale and busy drafts passed")
    }
}
