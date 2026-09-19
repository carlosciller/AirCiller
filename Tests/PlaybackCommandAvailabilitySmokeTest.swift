import Foundation

@main
struct PlaybackCommandAvailabilitySmokeTest {
    static func main() {
        let empty = state(hasFile: false, hasProbe: false, duration: 0)
        expect(
            !empty.canTogglePlayback && !empty.canSeek && !empty.canStop && !empty.canEditTracks,
            "An empty window cannot play, seek or edit nonexistent tracks")

        let pendingProbe = state(hasProbe: false, isAnalyzing: true)
        expectOnlyStop(pendingProbe, "Analysis is cancellable but cannot be labelled playable")
        let failedOrCancelledProbe = state(hasProbe: false)
        expect(
            !failedOrCancelledProbe.canTogglePlayback && !failedOrCancelledProbe.canEditTracks,
            "A failed or cancelled probe cannot enable Play or tracks")

        let ready = state()
        expect(
            ready.canTogglePlayback && ready.canSeek && ready.canEditTracks && !ready.canStop,
            "A prepared file keeps explicit Play, track editing and pre-play timeline positioning")
        expect(!ready.canChangeChapter, "A movie without chapters has no chapter command")
        expect(state(hasChapters: true).canChangeChapter, "Available chapters can be selected before Play")

        // No authorization boolean is inferred from unknown credentials. The
        // first allowed Play enters the ordinary preflight, which then blocks
        // duplicate keyboard/menu requests until success, failure or Stop.
        var starts = 0
        var current = ready
        for _ in 0..<4 {
            if current.canTogglePlayback {
                starts += 1
                current = state(isCheckingAuthorization: true)
            }
        }
        expect(starts == 1, "Repeated Play cannot restart a pending authorization request")
        expectOnlyStop(current, "Actual authorization checking retains cancellation")
        expectOnlyStop(state(isPreparing: true), "Preparation cannot be restarted or sought through a shortcut")
        expectOnlyStop(state(isPairing: true), "The code dialog owns authorization until completion or cancellation")
        expectOnlyStop(state(isAwaitingConversion: true), "The audio consent dialog cannot be bypassed by Play")
        expectOnlyStop(state(isWaitingToStart: true), "A pending automatic start must remain cancellable")

        var automaticStart = AutomaticPlaybackStartWait()
        expect(!automaticStart.isPending, "No automatic start is pending initially")
        let cancelledStart = automaticStart.begin()
        expectOnlyStop(
            state(isWaitingToStart: automaticStart.isPending),
            "The network-settling wait blocks duplicate Play and keeps Stop enabled")
        automaticStart.cancel()
        expect(!automaticStart.finish(cancelledStart), "Stop prevents the old task from claiming a start")
        let replacementStart = automaticStart.begin()
        expect(
            !automaticStart.finish(cancelledStart) && automaticStart.id == replacementStart,
            "An old task's deferred cleanup cannot clear a replacement start")
        expectOnlyStop(
            state(isWaitingToStart: automaticStart.isPending),
            "Replacement remains cancellable after old cleanup")
        expect(automaticStart.finish(replacementStart), "Only the current task can hand off playback")
        expect(!automaticStart.isPending, "Handoff ends the pending state")
        expect(!automaticStart.finish(replacementStart), "A start cannot be claimed twice")

        // Preparing a changed session can briefly retain streaming=true.
        // Busy must win over the previous session's ready controls.
        expectOnlyStop(
            state(isPreparing: true, isStreaming: true, hasChapters: true),
            "Old session state must not expose controls during track preparation")

        let active = state(isStreaming: true, hasChapters: true)
        expect(
            active.canTogglePlayback && active.canSeek && active.canStop && active.canEditTracks
                && active.canChangeChapter, "Stable playing and paused sessions share the same command availability")
        let directTestSession = state(hasFile: false, hasProbe: false, isStreaming: true)
        expect(
            directTestSession.canTogglePlayback && directTestSession.canSeek && directTestSession.canStop
                && !directTestSession.canEditTracks,
            "A receiver-owned test URL remains controllable without local tracks")

        for duration in [0, -1, Double.nan, Double.infinity] {
            let invalidTime = state(isStreaming: true, duration: duration, hasChapters: true)
            expect(
                !invalidTime.canSeek && !invalidTime.canChangeChapter && invalidTime.canStop,
                "Unknown or invalid duration disables timeline commands without losing Stop")
        }
        print("Playback command availability, busy-state exclusion and cancellation: OK")
    }

    private static func state(
        hasFile: Bool = true,
        hasProbe: Bool = true,
        isAnalyzing: Bool = false,
        isWaitingToStart: Bool = false,
        isPreparing: Bool = false,
        isStreaming: Bool = false,
        isCheckingAuthorization: Bool = false,
        isPairing: Bool = false,
        isAwaitingConversion: Bool = false,
        duration: Double = 120,
        hasChapters: Bool = false
    ) -> PlaybackCommandAvailability {
        PlaybackCommandAvailability(
            hasFile: hasFile, hasProbe: hasProbe, isAnalyzing: isAnalyzing,
            isWaitingToStart: isWaitingToStart,
            isPreparing: isPreparing, isStreaming: isStreaming,
            isCheckingAuthorization: isCheckingAuthorization, isPairing: isPairing,
            isAwaitingConversion: isAwaitingConversion, duration: duration, hasChapters: hasChapters
        )
    }

    private static func expectOnlyStop(_ state: PlaybackCommandAvailability, _ reason: String) {
        expect(
            state.canStop && !state.canTogglePlayback && !state.canSeek
                && !state.canEditTracks && !state.canChangeChapter, reason)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
}
