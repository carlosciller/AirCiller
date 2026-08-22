import Foundation

struct AirPlayPairingIntent: Sendable, Equatable {
    private(set) var shouldResumePlayback = false

    mutating func begin(resumePlayback: Bool) {
        shouldResumePlayback = resumePlayback
    }

    mutating func cancel() {
        shouldResumePlayback = false
    }

    mutating func consumeSuccess() -> Bool {
        let result = shouldResumePlayback
        shouldResumePlayback = false
        return result
    }
}
