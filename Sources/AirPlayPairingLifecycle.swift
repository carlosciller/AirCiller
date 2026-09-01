import Foundation

/// Prevents a new pairing helper from starting until the previous helper has
/// actually exited. The latest retry request wins; an explicit cancellation
/// discards every pending retry.
struct AirPlayPairingLifecycle: Sendable, Equatable {
    private(set) var pendingRestart: Bool?

    mutating func requestStart(resumePlayback: Bool, processIsActive: Bool) -> Bool {
        guard processIsActive else {
            pendingRestart = nil
            return true
        }
        pendingRestart = resumePlayback
        return false
    }

    mutating func cancel() {
        pendingRestart = nil
    }

    mutating func processDidTerminate() -> Bool? {
        defer { pendingRestart = nil }
        return pendingRestart
    }
}
