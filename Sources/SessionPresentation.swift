/// The visible phase of the session, without changing playback state. Pending
/// work takes precedence over the previous stream while tracks are replaced.
enum SessionPresentation: Equatable {
    case empty, unprepared, analyzing, waiting, preparing, ready, playing, paused, error

    init(
        hasFile: Bool, hasProbe: Bool, hasError: Bool,
        isAnalyzing: Bool, isWaiting: Bool, isPreparing: Bool,
        isStreaming: Bool, isPlaying: Bool
    ) {
        if isAnalyzing {
            self = .analyzing
        } else if isPreparing {
            self = .preparing
        } else if isWaiting {
            self = .waiting
        } else if isStreaming {
            self = isPlaying ? .playing : .paused
        } else if hasError {
            self = .error
        } else if !hasFile {
            self = .empty
        } else {
            self = hasProbe ? .ready : .unprepared
        }
    }

    var isBusy: Bool { self == .analyzing || self == .preparing || self == .waiting }
}
