import Foundation

/// A local, per-attempt measurement. Its endpoint is a receiver HTTP request,
/// not proof that the television displayed a frame or produced sound.
struct PlaybackStartupTrace: Sendable {
    enum Stage: String, Codable, CaseIterable, Sendable {
        case analysis, authorization, cacheLookup, cacheStore, packaging, subtitles, validation
        case localServer, localAsset, airPlay, receiverRequest
    }

    enum Outcome: String, Codable, Sendable {
        case prepared, receiverMediaRequest, cancelled, failed
    }

    enum SpanState: String, Codable, Sendable {
        case running, completed, interrupted, cancelled
    }

    struct SpanToken: Hashable, Sendable {
        fileprivate let sessionID: UUID
        fileprivate let id: UUID
    }

    struct Span: Codable, Equatable, Sendable {
        let stage: Stage
        let startSeconds: TimeInterval
        let elapsedSeconds: TimeInterval
        let state: SpanState
    }

    /// Fixed categories, relative times and a boot-relative monotonic origin
    /// for same-Mac test alignment. No wall-clock date, media names, paths,
    /// receiver identity, URLs or credentials enter this model.
    struct Snapshot: Codable, Equatable, Sendable {
        let sessionID: UUID
        let startedAtUptimeSeconds: TimeInterval
        let elapsedSeconds: TimeInterval
        let outcome: Outcome?
        let spans: [Span]
    }

    private struct Entry: Sendable {
        let token: SpanToken
        let stage: Stage
        let startedAt: TimeInterval
        var endedAt: TimeInterval?
        var state: SpanState = .running
    }

    let sessionID: UUID
    private let startedAt: TimeInterval
    private var lastEventAt: TimeInterval
    private var endedAt: TimeInterval?
    private var outcome: Outcome?
    private var entries: [Entry] = []

    /// Uptime is monotonic and unrelated to wall-clock corrections. Supplying
    /// timestamps makes tests deterministic without timers or background work.
    init(sessionID: UUID = UUID(), startedAt: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.sessionID = sessionID
        let validStart =
            startedAt.isFinite && startedAt >= 0
            ? startedAt : ProcessInfo.processInfo.systemUptime
        self.startedAt = validStart
        lastEventAt = validStart
    }

    /// Repeated begin calls during a stage return its existing token. Starting
    /// it again after completion creates a new span, safe from late callbacks.
    @discardableResult
    mutating func begin(
        _ stage: Stage,
        sessionID: UUID,
        at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> SpanToken? {
        guard accepts(sessionID: sessionID, timestamp: timestamp) else { return nil }
        if let active = entries.last(where: { $0.stage == stage && $0.endedAt == nil }) {
            return active.token
        }
        let token = SpanToken(sessionID: sessionID, id: UUID())
        entries.append(Entry(token: token, stage: stage, startedAt: timestamp))
        lastEventAt = timestamp
        return token
    }

    mutating func end(
        _ token: SpanToken?,
        sessionID: UUID,
        at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard accepts(sessionID: sessionID, timestamp: timestamp),
            let token, token.sessionID == sessionID,
            let index = entries.firstIndex(where: { $0.token == token && $0.endedAt == nil })
        else { return }
        entries[index].endedAt = timestamp
        entries[index].state = .completed
        lastEventAt = timestamp
    }

    /// Finishing seals the attempt. A dangling stage is not reported as
    /// completed merely because a request arrived or another operation failed.
    mutating func finish(
        _ outcome: Outcome,
        sessionID: UUID,
        at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        guard accepts(sessionID: sessionID, timestamp: timestamp) else { return }
        for index in entries.indices where entries[index].endedAt == nil {
            entries[index].endedAt = timestamp
            entries[index].state = outcome == .cancelled ? .cancelled : .interrupted
        }
        self.outcome = outcome
        endedAt = timestamp
        lastEventAt = timestamp
    }

    func snapshot(at timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) -> Snapshot {
        let observation = timestamp.isFinite ? max(lastEventAt, timestamp) : lastEventAt
        let end = endedAt ?? observation
        return Snapshot(
            sessionID: sessionID,
            startedAtUptimeSeconds: startedAt,
            elapsedSeconds: end - startedAt,
            outcome: outcome,
            spans: entries.map {
                Span(
                    stage: $0.stage,
                    startSeconds: $0.startedAt - startedAt,
                    elapsedSeconds: ($0.endedAt ?? end) - $0.startedAt,
                    state: $0.state
                )
            }
        )
    }

    private func accepts(sessionID: UUID, timestamp: TimeInterval) -> Bool {
        self.sessionID == sessionID && endedAt == nil
            && timestamp.isFinite && timestamp >= lastEventAt
    }
}
