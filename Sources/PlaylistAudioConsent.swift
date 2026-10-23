import Foundation

/// In-memory permission for equivalent conversions during one playback session.
/// Track names, language and stream indices may change between episodes.
struct PlaylistAudioConsent {
    private struct Treatment: Equatable {
        let codec: String
        let profile: String?
        let channels: Int
        let layout: String
        let sampleRate: Int?
        let precision: Int?

        init?(_ audio: AudioTrack) {
            guard let channels = audio.channels, channels > 0,
                let layout = audio.channelLayout, !layout.isEmpty
            else { return nil }
            codec = audio.codec.lowercased()
            profile = audio.profile?.lowercased()
            self.channels = channels
            self.layout = layout.lowercased()
            sampleRate = audio.sampleRate
            precision = audio.bitsPerSample
        }
    }

    private var treatment: Treatment?
    private var output: AudioOutputMode?

    mutating func authorize(audio: AudioTrack, output: AudioOutputMode) {
        guard output == .compatible || output == .losslessFLAC else { return }
        treatment = Treatment(audio)
        self.output = output
    }

    func authorizedOutput(for audio: AudioTrack, isDirectMP4: Bool, audioDelay: Double) -> AudioOutputMode? {
        guard !audio.canPassThrough, let treatment, treatment == Treatment(audio),
            let output, output.isAvailable(audio: audio, isDirectMP4: isDirectMP4),
            output != .losslessFLAC || (audioDelay.isFinite && abs(audioDelay) < 0.001)
        else { return nil }
        return output
    }

    mutating func reset() {
        treatment = nil
        output = nil
    }
}
