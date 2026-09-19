import Foundation

/// The same command rules are used by transport buttons, menus and shortcuts.
/// Unknown authorization is not a pending operation: the first Play must be
/// allowed to initiate its existing authorization preflight.
struct PlaybackCommandAvailability: Equatable, Sendable {
    let hasFile: Bool
    let hasProbe: Bool
    let isAnalyzing: Bool
    let isWaitingToStart: Bool
    let isPreparing: Bool
    let isStreaming: Bool
    let isCheckingAuthorization: Bool
    let isPairing: Bool
    let isAwaitingConversion: Bool
    let duration: Double
    let hasChapters: Bool

    private var isBusy: Bool {
        isAnalyzing || isWaitingToStart || isPreparing || isCheckingAuthorization || isPairing || isAwaitingConversion
    }

    var canTogglePlayback: Bool {
        !isBusy && (isStreaming || (hasFile && hasProbe))
    }

    var canSeek: Bool {
        !isBusy && duration.isFinite && duration > 0 && (isStreaming || (hasFile && hasProbe))
    }

    var canStop: Bool {
        isBusy || isStreaming
    }

    var canEditTracks: Bool {
        !isBusy && hasFile && hasProbe
    }

    var canChangeChapter: Bool {
        canSeek && hasChapters
    }
}

/// Owns the cancellable interval between probing a movie and handing its
/// automatic start to the existing playback pipeline. An obsolete task's
/// cleanup must not release a replacement movie's pending start.
struct AutomaticPlaybackStartWait: Equatable, Sendable {
    private(set) var id: UUID?

    var isPending: Bool { id != nil }

    mutating func begin() -> UUID {
        let newID = UUID()
        id = newID
        return newID
    }

    @discardableResult
    mutating func finish(_ expectedID: UUID) -> Bool {
        guard id == expectedID else { return false }
        id = nil
        return true
    }

    mutating func cancel() {
        id = nil
    }
}
