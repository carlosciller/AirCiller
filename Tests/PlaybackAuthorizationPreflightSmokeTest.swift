import Foundation

@main
struct PlaybackAuthorizationPreflightSmokeTest {
    @MainActor
    static func main() async throws {
        let preflight = PlaybackAuthorizationPreflight()
        var events: [String] = []
        let first = Gate()
        preflight.start {
            await first.wait()
        } onSuccess: {
            events.append("cancelled playback")
        } onFailure: { _ in
            events.append("cancelled failure")
        }
        await first.waitUntilStarted()
        preflight.cancel()
        first.release()
        await drain()
        guard events.isEmpty else { throw Failure.cancelledRequestResumed }

        let old = Gate()
        preflight.start {
            await old.wait()
            throw Failure.obsoleteError
        } onSuccess: {
            events.append("old playback")
        } onFailure: { _ in
            events.append("old failure")
        }
        await old.waitUntilStarted()
        preflight.start {
        } onSuccess: {
            events.append("new playback")
        } onFailure: { _ in
            events.append("new failure")
        }
        await drain()
        old.release()
        await drain()
        guard events == ["new playback"] else { throw Failure.obsoleteRequestWon }

        preflight.start {
            throw Failure.obsoleteError
        } onSuccess: {
            events.append("unexpected success")
        } onFailure: { _ in
            events.append("current failure")
        }
        await drain()
        guard events == ["new playback", "current failure"] else { throw Failure.missingFailure }
        print("Stop and replacement invalidate delayed authorization success and failure: OK")
    }

    @MainActor
    private static func drain() async {
        for _ in 0..<20 { await Task.yield() }
    }

    private enum Failure: Error {
        case cancelledRequestResumed, obsoleteRequestWon, missingFailure, obsoleteError
    }

    /// Deliberately ignores cancellation, like a Keychain request already in flight.
    @MainActor
    private final class Gate {
        private var continuation: CheckedContinuation<Void, Never>?

        func wait() async {
            await withCheckedContinuation { continuation = $0 }
        }

        func waitUntilStarted() async {
            while continuation == nil { await Task.yield() }
        }

        func release() {
            continuation?.resume()
            continuation = nil
        }
    }
}
