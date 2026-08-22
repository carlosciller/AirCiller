import Foundation

@main
struct AirPlayAuthorizationRetryPolicySmokeTest {
    static func main() throws {
        var policy = AirPlayAuthorizationRetryPolicy()

        guard policy.beginRenewal(),
            !policy.beginRenewal(),
            policy.renewalAttempts == 1
        else {
            throw NSError(domain: "AirPlayAuthorizationRetryPolicySmokeTest.LoopGuard", code: 1)
        }

        policy.reset()
        guard policy.beginRenewal(), policy.renewalAttempts == 1 else {
            throw NSError(domain: "AirPlayAuthorizationRetryPolicySmokeTest.Reset", code: 2)
        }

        print("Autorización AirPlay limitada a una renovación automática: OK")
    }
}
