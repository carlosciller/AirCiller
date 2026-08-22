import Foundation

struct AirPlayAuthorizationRetryPolicy: Sendable {
    private(set) var renewalAttempts = 0

    mutating func reset() {
        renewalAttempts = 0
    }

    mutating func beginRenewal() -> Bool {
        guard renewalAttempts == 0 else { return false }
        renewalAttempts = 1
        return true
    }
}
