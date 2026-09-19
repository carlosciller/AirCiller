import Foundation

@main
struct AirCillerErrorRecoverySmokeTest {
    static func main() {
        let missingEngines: [(AirCillerError, String)] = [
            (.ffmpegMissing, "FFmpeg"), (.ffprobeMissing, "ffprobe"),
        ]
        for (error, tool) in missingEngines {
            let message = error.localizedDescription
            precondition(message.contains(tool), "Recovery identifies the missing bundled tool")
            precondition(message.contains("AirCiller"), "Recovery identifies the app that needs repair")
            precondition(
                !message.localizedCaseInsensitiveContains("Homebrew"),
                "A missing bundled engine must never direct users to a host-engine fallback")
            precondition(
                message.localizedCaseInsensitiveContains("instalar AirCiller")
                    || message.localizedCaseInsensitiveContains("install AirCiller"),
                "Recovery asks users to reinstall AirCiller, not install an independent codec"
            )
        }
        let probeFailure = AirCillerError.probeFailed("Synthetic probe detail").localizedDescription
        precondition(probeFailure.contains("Synthetic probe detail"), "File-analysis errors retain their actual cause")
        let processFailure = AirCillerError.ffmpegStopped("Synthetic process detail").localizedDescription
        precondition(
            processFailure == "El motor se detuvo: Synthetic process detail",
            "Process failure stays distinct from a missing installation")
        precondition(
            !AirCillerError.ffmpegStopped("").localizedDescription.isEmpty,
            "An engine failure without stderr still has an understandable message")
        print("Bundled-engine recovery instructions and preserved failure details: OK")
    }
}
