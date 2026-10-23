import Foundation

@main
struct PlaylistAudioConsentSmokeTest {
    static func main() {
        func track(codec: String = "truehd", channels: Int = 6, layout: String = "5.1(side)", index: Int = 1)
            -> AudioTrack
        {
            AudioTrack(
                streamIndex: index, codec: codec, profile: nil, channels: channels,
                channelLayout: layout, language: "eng", title: nil, isDefault: true,
                sampleRate: 48_000, bitsPerSample: 24)
        }
        var consent = PlaylistAudioConsent()
        let first = track()
        func output(_ audio: AudioTrack) -> AudioOutputMode? {
            consent.authorizedOutput(for: audio, isDirectMP4: false, audioDelay: 0)
        }
        precondition(output(first) == nil)
        consent.authorize(audio: first, output: .compatible)
        precondition(output(track(index: 3)) == .compatible)
        precondition(output(track(codec: "eac3")) == nil)
        precondition(output(track(channels: 2, layout: "stereo")) == nil)
        precondition(output(track(channels: 8, layout: "7.1")) == nil)
        precondition(output(track(codec: "dts")) == nil)
        consent.authorize(audio: first, output: .losslessFLAC)
        precondition(output(first) == .losslessFLAC)
        precondition(consent.authorizedOutput(for: first, isDirectMP4: true, audioDelay: 0) == nil)
        precondition(consent.authorizedOutput(for: first, isDirectMP4: false, audioDelay: 0.5) == nil)
        consent.reset()
        precondition(output(first) == nil)
        print("Playlist audio consent: OK")
    }
}
