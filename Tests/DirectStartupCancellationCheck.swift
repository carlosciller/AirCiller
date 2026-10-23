import Foundation

/// Uses the direct-startup ownership checkpoint after a controlled suspension.
/// No media, receiver, daily preferences or installed app is involved.
enum DirectStartupCancellationCheck {
    @MainActor static func run() async throws {
        let coordinator = StreamCoordinator()
        coordinator.beginSyntheticPlaybackSessionForChecks()
        try await coordinator.directStartupCheckpointForChecks(after: {})

        try await expectCancellation {
            try await coordinator.directStartupCheckpointForChecks {
                coordinator.stop()
            }
        }

        coordinator.beginSyntheticPlaybackSessionForChecks()
        try await expectCancellation {
            try await coordinator.directStartupCheckpointForChecks {
                coordinator.stop()
                coordinator.beginSyntheticPlaybackSessionForChecks()
            }
        }
        try require(coordinator.isStreaming, "An old direct startup must leave the replacement session active")
        try require(
            coordinator.playbackPowerIsActiveForChecks, "An old startup must preserve replacement power ownership")

        let entered = Suspension()
        let resume = Suspension()
        let task = Task { @MainActor in
            try await coordinator.directStartupCheckpointForChecks {
                entered.release()
                await resume.wait()
            }
        }
        await entered.wait()
        task.cancel()
        resume.release()
        try await expectCancellation { try await task.value }
        try require(coordinator.isStreaming, "Cancellation must be rejected even while the session ID still matches")
        coordinator.stop()
        try pairingCancellation()
        print("Direct startup: cancelled and superseded continuations rejected at player checkpoints: OK")
    }

    @MainActor private static func pairingCancellation() throws {
        let coordinator = StreamCoordinator()
        coordinator.beginSyntheticAuthorizationRenewalForChecks()
        try require(coordinator.playbackPowerIsActiveForChecks, "Autoplay must stay awake through authorization")
        coordinator.airPlay.cancelPairing()
        try require(
            !coordinator.playbackPowerIsActiveForChecks, "Cancelling authorization must release transition power")
        try require(!coordinator.isPreparing && !coordinator.isStreaming, "Cancellation must leave no pending playback")

        coordinator.beginSyntheticAuthorizationRenewalForChecks()
        coordinator.stop(resetStatus: false, preservingTransition: true)
        try require(
            coordinator.playbackPowerIsActiveForChecks,
            "Teardown of old pairing must not release a replacement transition")
        coordinator.beginSyntheticPlaybackSessionForChecks()
        coordinator.status = "replacement"
        coordinator.airPlay.cancelPairing()
        try require(
            coordinator.isStreaming && coordinator.status == "replacement"
                && coordinator.playbackPowerIsActiveForChecks,
            "A late pairing cancellation must not alter a replacement session")
        coordinator.stop()
    }

    @MainActor private static func expectCancellation(_ operation: () async throws -> Void) async throws {
        do {
            try await operation()
            throw Failure(message: "A retired direct startup resumed")
        } catch is CancellationError {}
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw Failure(message: message) }
    }

    private struct Failure: Error { let message: String }

    @MainActor private final class Suspension {
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false

        func wait() async {
            if released { return }
            await withCheckedContinuation { continuation = $0 }
        }

        func release() {
            released = true
            continuation?.resume()
            continuation = nil
        }
    }
}
