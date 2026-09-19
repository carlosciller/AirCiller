@main
struct SessionPresentationSmokeTest {
    static func main() {
        precondition(phase(hasFile: false, hasProbe: false) == .empty)
        precondition(phase(hasProbe: false) == .unprepared)
        precondition(phase(hasProbe: false, analyzing: true) == .analyzing)
        precondition(phase() == .ready, "A probed file must not look like active playback")
        precondition(phase(streaming: true, playing: true) == .playing)
        precondition(phase(streaming: true) == .paused)
        precondition(phase(playing: true) == .ready, "A stale playing flag is not an active stream")
        precondition(phase(preparing: true, streaming: true, playing: true) == .preparing)
        precondition(phase(waiting: true, streaming: true, playing: true) == .waiting)
        precondition(phase(error: true) == .error)
        precondition(
            phase(error: true, streaming: true, playing: true) == .playing,
            "A failed subtitle import must not hide controls or relabel Pause as Play")
        precondition(phase(error: true, streaming: true) == .paused)
        precondition(phase(error: true, preparing: true) == .preparing)
        precondition(phase(waiting: true).isBusy)
        precondition(phase(analyzing: true).isBusy)
        precondition(phase(preparing: true).isBusy)
        precondition(!phase().isBusy && !phase(error: true).isBusy)
        print("Session presentation: ready, active, pending and recovery phases: OK")
    }

    private static func phase(
        hasFile: Bool = true, hasProbe: Bool = true, error: Bool = false,
        analyzing: Bool = false, waiting: Bool = false, preparing: Bool = false,
        streaming: Bool = false, playing: Bool = false
    ) -> SessionPresentation {
        SessionPresentation(
            hasFile: hasFile, hasProbe: hasProbe, hasError: error,
            isAnalyzing: analyzing, isWaiting: waiting, isPreparing: preparing,
            isStreaming: streaming, isPlaying: playing
        )
    }
}
