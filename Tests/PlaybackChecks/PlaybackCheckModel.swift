import Foundation

// Compiled into the opt-in check app and deterministic tests only.
struct PlaybackCheckPlan: Decodable {
    enum Route: String, Codable { case directHDR, hls }
    enum Profile: String, Codable {
        case controls, trackChanges, cancelPreparation, playlistTransition, longPause, cancelBitmap
    }

    struct NextClip: Decodable {
        let path: String
        let route: Route
    }

    struct Clip: Decodable {
        let path: String
        let route: Route
        let subtitleIndex: Int?
        let externalSubtitle: String?
        let alternateSubtitle: String?
        let nextClip: NextClip?

        func validate() throws {
            guard path.hasPrefix("/"),
                ["mp4", "m4v", "mkv", "mov"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()),
                subtitleIndex.map({ $0 >= 0 }) ?? true,
                subtitleIndex == nil || externalSubtitle == nil,
                route != .directHDR || subtitleIndex != nil || externalSubtitle != nil
            else { throw PlaybackCheckFailure.invalidPlan }
            if let externalSubtitle {
                guard externalSubtitle.hasPrefix("/"),
                    ["srt", "ass", "ssa", "vtt"].contains(
                        URL(fileURLWithPath: externalSubtitle).pathExtension.lowercased())
                else { throw PlaybackCheckFailure.invalidPlan }
            }
            if let alternateSubtitle {
                guard alternateSubtitle.hasPrefix("/"), alternateSubtitle != externalSubtitle,
                    URL(fileURLWithPath: alternateSubtitle).pathExtension.lowercased() == "srt"
                else { throw PlaybackCheckFailure.invalidPlan }
            }
            if let nextClip {
                guard nextClip.path.hasPrefix("/"), nextClip.path != path, nextClip.route == .hls,
                    ["mp4", "m4v", "mkv", "mov"].contains(
                        URL(fileURLWithPath: nextClip.path).pathExtension.lowercased())
                else { throw PlaybackCheckFailure.invalidPlan }
            }
        }
    }

    let version: Int
    let deviceID: String
    let clips: [Clip]
    let captureReadyFile: String?
    let profile: Profile?
    var selectedProfile: Profile { profile ?? .controls }

    static func decode(_ data: Data) throws -> Self {
        guard data.count <= 65_536 else { throw PlaybackCheckFailure.invalidPlan }
        let plan: Self
        do { plan = try JSONDecoder().decode(Self.self, from: data) } catch { throw PlaybackCheckFailure.invalidPlan }
        guard plan.version == 1, !plan.deviceID.isEmpty, plan.deviceID.count <= 256,
            (1...6).contains(plan.clips.count)
        else { throw PlaybackCheckFailure.invalidPlan }
        if let marker = plan.captureReadyFile {
            guard marker.hasPrefix("/"), marker.utf8.count <= 4_096,
                URL(fileURLWithPath: marker).pathExtension == "ready"
            else { throw PlaybackCheckFailure.invalidPlan }
        }
        for clip in plan.clips { try clip.validate() }
        if plan.selectedProfile != .controls && plan.selectedProfile != .cancelBitmap {
            guard plan.clips.count == 1 else { throw PlaybackCheckFailure.invalidPlan }
        }
        if plan.selectedProfile == .cancelBitmap {
            guard plan.deviceID == "local-only", plan.captureReadyFile == nil,
                plan.clips.count >= 2, Set(plan.clips.map(\.path)).count == plan.clips.count,
                plan.clips.allSatisfy({ $0.subtitleIndex != nil && $0.externalSubtitle == nil })
            else { throw PlaybackCheckFailure.invalidPlan }
        }
        for clip in plan.clips {
            guard (clip.alternateSubtitle != nil) == (plan.selectedProfile == .trackChanges),
                (clip.nextClip != nil) == (plan.selectedProfile == .playlistTransition)
            else { throw PlaybackCheckFailure.invalidPlan }
            if [.trackChanges, .playlistTransition, .longPause].contains(plan.selectedProfile) {
                guard clip.externalSubtitle != nil else { throw PlaybackCheckFailure.invalidPlan }
            }
            if plan.selectedProfile == .playlistTransition, clip.route != .directHDR {
                throw PlaybackCheckFailure.invalidPlan
            }
            if plan.selectedProfile == .cancelPreparation,
                plan.captureReadyFile != nil || clip.route != .hls || clip.externalSubtitle != nil
                    || clip.subtitleIndex != nil
            {
                throw PlaybackCheckFailure.invalidPlan
            }
        }
        return plan
    }
}

enum PlaybackCheckFailure: String, Error, Codable {
    case invalidPlan, missingMedia, wrongBuild, appAlreadyRunning, playbackNotAuthorized
    case deviceUnavailable, authorizationUnavailable, conversionRequested, unsupportedFixture
    case applicationError, receiverMismatch, unexpectedTerminalEvent, timedOut, evidenceLimit, cleanupFailed,
        interrupted

    var outcome: String {
        switch self {
        case .timedOut: "inconclusive"
        case .deviceUnavailable, .authorizationUnavailable, .unsupportedFixture, .missingMedia,
            .wrongBuild, .appAlreadyRunning, .playbackNotAuthorized, .invalidPlan:
            "blocked"
        default: "failed"
        }
    }
}

struct PlaybackCheckEvent: Codable {
    enum Origin: String, Codable { case receiver, command, helper }
    let seconds: Double
    let kind: String
    let origin: Origin
    let position: Double?
    let duration: Double?
    let playing: Bool?
    let requestID: String?

    init?(
        seconds: Double, kind: String, source: String? = nil,
        position: Double? = nil, duration: Double? = nil, playing: Bool? = nil, requestID: String? = nil
    ) {
        guard seconds.isFinite, seconds >= 0,
            ["playing", "status", "paused", "resumed", "seeked", "waiting", "ended", "stopped", "error", "accepted"]
                .contains(kind)
        else { return nil }
        self.seconds = seconds
        self.kind = kind
        // `stopped` can be a local shutdown reply; never call it receiver evidence.
        if source == "command" || kind == "seeked" {
            origin = .command
        } else if ["playing", "status", "ended"].contains(kind)
            || (["paused", "resumed"].contains(kind) && source == "receiver")
        {
            origin = .receiver
        } else {
            origin = .helper
        }
        self.position = position.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.duration = duration.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.playing = playing
        self.requestID = requestID.flatMap { UUID(uuidString: $0)?.uuidString }
    }

    var receiverIsPlaying: Bool? {
        guard origin == .receiver else { return nil }
        if kind == "paused" { return false }
        if kind == "playing" || kind == "resumed" { return true }
        return playing
    }
}

enum PlaybackCheckControl {
    // A test's requested state must not invert when the receiver changes state.
    static func request(playing: Bool, pause: () -> Bool, resume: () -> Bool) -> Bool {
        playing ? resume() : pause()
    }
}

enum PlaybackCheckEvidence {
    enum Verdict { case confirmed, missing, mismatch }

    static func resumedAt(_ events: ArraySlice<PlaybackCheckEvent>, target: Double) -> Verdict {
        guard target.isFinite, target >= 0 else { return .mismatch }
        guard let receiver = events.first(where: { $0.receiverIsPlaying == true && $0.position != nil }),
            let position = receiver.position
        else { return .missing }
        return abs(position - target) <= 2 ? .confirmed : .mismatch
    }

    static func singlePlaylistTransition(loads: [Int], events: ArraySlice<PlaybackCheckEvent>) -> Bool {
        guard loads == [1, 2] else { return false }
        let ends = events.filter { $0.kind == "ended" && $0.origin == .receiver }
        guard ends.count == 1, let end = ends.first else { return false }
        return events.contains { $0.kind == "playing" && $0.origin == .receiver && $0.seconds > end.seconds }
    }

    static func progressVerdict(_ events: ArraySlice<PlaybackCheckEvent>) -> Verdict {
        if hasProgress(events) { return .confirmed }
        let samples = events.filter { $0.origin == .receiver && $0.position != nil }
        guard let first = samples.first, first.receiverIsPlaying == true,
            let last = samples.last, last.seconds - first.seconds >= 0.75
        else { return .missing }
        return .mismatch
    }

    static func seekVerdict(_ events: ArraySlice<PlaybackCheckEvent>, target: Double, count: Int) -> Verdict {
        if settledSeek(events, target: target, count: count, playing: true) { return .confirmed }
        guard let lastAck = events.last(where: { $0.kind == "seeked" }),
            events.contains(where: { $0.origin == .receiver && $0.position != nil && $0.seconds >= lastAck.seconds })
        else { return .missing }
        return .mismatch
    }

    static func seekCommandsAcknowledged(
        _ events: ArraySlice<PlaybackCheckEvent>, target: Double, count: Int
    ) -> Bool {
        let acknowledgements = events.filter { $0.kind == "seeked" && $0.requestID != nil }
        guard Set(acknowledgements.compactMap(\.requestID)).count == count,
            let lastPosition = acknowledgements.last?.position
        else { return false }
        return abs(lastPosition - target) <= 0.1
    }

    static func hasProgress(_ events: ArraySlice<PlaybackCheckEvent>) -> Bool {
        let samples = events.filter { $0.receiverIsPlaying != nil && $0.position != nil }
        guard let first = samples.first, let initial = first.position else { return false }
        guard first.receiverIsPlaying == true else { return false }
        return samples.dropFirst().contains {
            guard let position = $0.position else { return false }
            let elapsed = $0.seconds - first.seconds
            let advanced = position - initial
            // A single seek, duplicate status or locally extrapolated timer is insufficient.
            return elapsed >= 0.75 && advanced >= 0.5 && advanced <= elapsed + 2
        }
    }

    static func paused(_ events: ArraySlice<PlaybackCheckEvent>) -> Bool {
        events.last(where: { $0.receiverIsPlaying != nil })?.receiverIsPlaying == false
    }

    static func settledSeek(
        _ events: ArraySlice<PlaybackCheckEvent>, target: Double, count: Int, playing: Bool = false
    ) -> Bool {
        let acknowledgements = events.filter { $0.kind == "seeked" && $0.requestID != nil }
        guard Set(acknowledgements.compactMap(\.requestID)).count == count,
            let lastAck = acknowledgements.last,
            let lastAckPosition = lastAck.position, abs(lastAckPosition - target) <= 0.1,
            let receiver = events.last(where: { $0.origin == .receiver && $0.position != nil }),
            receiver.seconds >= lastAck.seconds, receiver.receiverIsPlaying == playing,
            let position = receiver.position
        else { return false }
        return abs(position - target) <= 2
    }
}

struct PlaybackCheckResult: Encodable {
    let clip: Int
    let route: PlaybackCheckPlan.Route
    let subtitlesRequested: Bool
    var completedSteps: [String] = []
    var unverifiedChecks: [String] = []
    var failure: PlaybackCheckFailure?
    var failedStep: String?
    var events: [PlaybackCheckEvent] = []
    var elapsedSeconds: Double = 0
    var startedAtUptime: Double?
    var cleanupConfirmed = false
    var profile: PlaybackCheckPlan.Profile = .controls
    var outputWindows: [PlaybackCheckOutputWindow] = []
    var loadSequence: [Int] = []
    var pauseWindow: PlaybackCheckOutputWindow?
    var bitmapCancellation: BitmapCancellationEvidence?
}

struct BitmapCancellationEvidence: Encodable {
    let phase: String
    let codec: String
    let cancellationSeconds: Double
    let recognizedCuesBeforeStop: Int
}

struct PlaybackCheckOutputWindow: Encodable {
    let label: String
    let startedAtUptime: Double
    let endedAtUptime: Double
}

struct PlaybackCheckReport: Encodable {
    let schemaVersion = 1
    let appVersion: String
    var outcome: String
    var failure: PlaybackCheckFailure?
    var results: [PlaybackCheckResult] = []
    let outputVerification = "not_observed"
    let unobservedOutputChecks = [
        "Picture and HDR/Dolby Vision appearance for each selected clip",
        "Audible sound and correct channels for each selected clip",
        "Subtitles visible, selectable and synchronized where requested; absent otherwise",
        "Physical Apple TV and iPhone Remote commands remain synchronized",
        "Playback progress and seek destination wherever receiver positions were unavailable",
    ]
}
