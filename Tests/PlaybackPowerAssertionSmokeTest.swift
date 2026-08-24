import Foundation

@main
struct PlaybackPowerAssertionSmokeTest {
    @MainActor
    static func main() throws {
        let assertion = PlaybackPowerAssertion()
        guard !assertion.isActive else {
            throw NSError(domain: "PlaybackPowerAssertionSmokeTest.Initial", code: 1)
        }

        assertion.begin()
        assertion.begin()
        guard assertion.isActive else {
            throw NSError(domain: "PlaybackPowerAssertionSmokeTest.Begin", code: 2)
        }

        assertion.end()
        assertion.end()
        guard !assertion.isActive else {
            throw NSError(domain: "PlaybackPowerAssertionSmokeTest.End", code: 3)
        }

        print("Automatic sleep blocked idempotently during the session: OK")
    }
}
