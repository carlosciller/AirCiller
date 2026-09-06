import Foundation
import Security

@main
enum PlaybackCheckKeychainSmokeTest {
    static func main() throws {
        guard ACPlaybackChecksDisableKeychainUI() == errSecSuccess,
            ACPlaybackChecksDisableKeychainUI() == errSecSuccess
        else { throw NSError(domain: "PlaybackChecks.KeychainUI", code: 1) }
        print("Playback checks disable and verify process-local Keychain interaction: OK")
    }
}
