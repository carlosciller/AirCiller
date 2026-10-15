import Foundation

@main
struct PCMAudioEligibilitySmokeTest {
    static func main() throws {
        func track(
            codec: String = "pcm_s24le", channels: Int? = 2, layout: String? = "stereo",
            rate: Int? = 48_000, bits: Int? = 24
        ) -> AudioTrack {
            AudioTrack(
                streamIndex: 1, codec: codec, profile: nil, channels: channels, channelLayout: layout,
                language: nil, title: nil, isDefault: true, sampleRate: rate, bitsPerSample: bits)
        }
        for (channels, layout) in [(1, "mono"), (2, "stereo"), (6, "5.1(side)"), (8, "7.1")] {
            guard track(channels: channels, layout: layout).canPrepareLosslessFLAC else {
                throw Failure.rejectedKnownLayout
            }
            guard track(codec: "truehd", channels: channels, layout: layout).canPrepareLosslessFLAC else {
                throw Failure.rejectedKnownLayout
            }
        }
        for unsupported in [
            track(rate: nil), track(rate: 0), track(bits: nil), track(bits: 32), track(bits: 16),
            track(codec: "pcm_bluray", bits: 20),
            track(channels: nil), track(layout: nil), track(layout: "unknown"),
            track(channels: 6, layout: "5.1"), track(channels: 2, layout: "7.1"),
            track(codec: "pcm_f32le"), track(codec: "truehd", bits: 16),
            track(codec: "truehd", rate: 32_000), track(codec: "dts"),
        ] {
            guard !unsupported.canPrepareLosslessFLAC else { throw Failure.acceptedUnsafeInput }
        }
        guard track(codec: "pcm_s16be", bits: 16).canPrepareLosslessFLAC,
            track(codec: "pcm_bluray", bits: 24).canPrepareLosslessFLAC,
            !track().canPassThrough,
            AudioOutputMode.losslessFLAC.isAvailable(audio: track(), isDirectMP4: false),
            !AudioOutputMode.losslessFLAC.isAvailable(audio: track(), isDirectMP4: true),
            !AudioOutputMode.losslessFLAC.isAvailable(audio: nil, isDirectMP4: false),
            !AudioOutputMode.losslessFLAC.isAvailable(audio: track(layout: nil), isDirectMP4: false)
        else { throw Failure.originalPolicyChanged }
        print(
            "PCM/TrueHD lossless eligibility: verified precision/rates and native layouts; original policy unchanged: OK"
        )
    }

    private enum Failure: Error {
        case rejectedKnownLayout, acceptedUnsafeInput, originalPolicyChanged
    }
}
