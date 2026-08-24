import Foundation

@main
struct AirPlayPairingIntentSmokeTest {
    static func main() throws {
        var intent = AirPlayPairingIntent()

        intent.begin(resumePlayback: false)
        guard !intent.consumeSuccess() else {
            throw NSError(domain: "AirPlayPairingIntentSmokeTest.Manual", code: 1)
        }

        intent.begin(resumePlayback: true)
        guard intent.shouldResumePlayback, intent.consumeSuccess(), !intent.shouldResumePlayback else {
            throw NSError(domain: "AirPlayPairingIntentSmokeTest.Playback", code: 2)
        }

        intent.begin(resumePlayback: true)
        intent.cancel()
        guard !intent.shouldResumePlayback else {
            throw NSError(domain: "AirPlayPairingIntentSmokeTest.Cancel", code: 3)
        }

        print("Manual pairing kept separate from playback resume: OK")
    }
}
