import Foundation

@main
struct AirPlayPairingLifecycleSmokeTest {
    static func main() throws {
        var lifecycle = AirPlayPairingLifecycle()

        guard lifecycle.requestStart(resumePlayback: false, processIsActive: false) else {
            throw NSError(domain: "AirPlayPairingLifecycleSmokeTest.Initial", code: 1)
        }

        guard !lifecycle.requestStart(resumePlayback: false, processIsActive: true),
            lifecycle.pendingRestart == false,
            !lifecycle.requestStart(resumePlayback: true, processIsActive: true),
            lifecycle.pendingRestart == true,
            lifecycle.processDidTerminate() == true,
            lifecycle.pendingRestart == nil
        else {
            throw NSError(domain: "AirPlayPairingLifecycleSmokeTest.Restart", code: 2)
        }

        _ = lifecycle.requestStart(resumePlayback: true, processIsActive: true)
        lifecycle.cancel()
        guard lifecycle.processDidTerminate() == nil else {
            throw NSError(domain: "AirPlayPairingLifecycleSmokeTest.Cancel", code: 3)
        }

        print("Pairing retries wait for termination and explicit cancellation wins: OK")
    }
}
