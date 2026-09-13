import Foundation

@main
struct PlaybackStartupTraceSmokeTest {
    static func main() throws {
        try overlappingStages()
        try repeatedAndStaleCallbacks()
        try cancellationAndFailure()
        try invalidClocks()
        try serializationBoundary()
        print("Startup timing: overlapping phases, stale sessions, cancellation and private snapshots: OK")
    }

    private static func overlappingStages() throws {
        let session = UUID()
        var trace = PlaybackStartupTrace(sessionID: session, startedAt: 100)
        let packaging = trace.begin(.packaging, sessionID: session, at: 102)
        let subtitles = trace.begin(.subtitles, sessionID: session, at: 104)
        trace.end(subtitles, sessionID: session, at: 110)
        trace.end(packaging, sessionID: session, at: 112)
        let request = trace.begin(.receiverRequest, sessionID: session, at: 112)
        trace.end(request, sessionID: session, at: 114)
        trace.finish(.receiverMediaRequest, sessionID: session, at: 114)
        let result = trace.snapshot(at: 200)
        try require(result.startedAtUptimeSeconds == 100, "retain monotonic origin for same-Mac timing alignment")
        try require(result.elapsedSeconds == 14, "overlapping phases must not be summed as total startup")
        try require(result.spans.map(\.elapsedSeconds) == [10, 6, 2], "individual phase durations")
        try require(result.spans.map(\.startSeconds) == [2, 4, 12], "relative phase starts")
        try require(result.spans.allSatisfy { $0.state == .completed }, "explicitly ended spans")
        try require(result.outcome == .receiverMediaRequest, "HTTP request is the endpoint, not a visible frame")
        try require(trace.begin(.airPlay, sessionID: session, at: 201) == nil, "finished attempt cannot restart")
        trace.finish(.failed, sessionID: session, at: 202)
        try require(trace.snapshot(at: 203) == result, "finished measurements must stay immutable")
    }

    private static func repeatedAndStaleCallbacks() throws {
        let session = UUID()
        var trace = PlaybackStartupTrace(sessionID: session, startedAt: 0)
        let first = trace.begin(.authorization, sessionID: session, at: 1)
        let duplicate = trace.begin(.authorization, sessionID: session, at: 2)
        try require(first != nil && duplicate == first, "duplicate begin should reuse the active span")
        trace.end(first, sessionID: session, at: 3)
        let second = trace.begin(.authorization, sessionID: session, at: 4)
        trace.end(first, sessionID: session, at: 5)
        let wrongSession = UUID()
        trace.end(second, sessionID: wrongSession, at: 6)
        trace.finish(.cancelled, sessionID: wrongSession, at: 6)
        try require(trace.begin(.airPlay, sessionID: wrongSession, at: 6) == nil, "ignore obsolete session begin")
        let running = trace.snapshot(at: 6)
        try require(running.spans.count == 2 && running.spans[1].state == .running, "stale end must not close new span")
        var replacement = PlaybackStartupTrace(sessionID: UUID(), startedAt: 0)
        let replacementToken = replacement.begin(.authorization, sessionID: replacement.sessionID, at: 1)
        replacement.end(second, sessionID: replacement.sessionID, at: 2)
        try require(
            replacement.snapshot(at: 2).spans[0].state == .running, "foreign attempt token must not close a span")
        replacement.end(replacementToken, sessionID: replacement.sessionID, at: 3)
        trace.end(second, sessionID: session, at: 7)
        try require(
            trace.snapshot(at: 7).spans.map(\.elapsedSeconds) == [2, 3], "repeated phase has independent timing")
    }

    private static func cancellationAndFailure() throws {
        for outcome in [PlaybackStartupTrace.Outcome.cancelled, .failed, .prepared, .receiverMediaRequest] {
            let session = UUID()
            var trace = PlaybackStartupTrace(sessionID: session, startedAt: 10)
            let completed = trace.begin(.authorization, sessionID: session, at: 10)
            trace.end(completed, sessionID: session, at: 11)
            let dangling = trace.begin(.packaging, sessionID: session, at: 12)
            trace.finish(outcome, sessionID: session, at: 15)
            trace.end(dangling, sessionID: session, at: 100)
            let result = trace.snapshot(at: 100)
            try require(result.outcome == outcome && result.elapsedSeconds == 5, "seal on termination")
            try require(result.spans[0].state == .completed, "preserve completed work on termination")
            try require(result.spans[1].elapsedSeconds == 3, "close dangling timing at termination")
            let expected: PlaybackStartupTrace.SpanState = outcome == .cancelled ? .cancelled : .interrupted
            try require(result.spans[1].state == expected, "do not mislabel dangling work as completed")
        }
    }

    private static func invalidClocks() throws {
        let session = UUID()
        var trace = PlaybackStartupTrace(sessionID: session, startedAt: 10)
        let token = trace.begin(.localServer, sessionID: session, at: 12)
        for invalid in [Double.nan, .infinity, -.infinity, -1, 9, 11] {
            try require(
                trace.begin(.localAsset, sessionID: session, at: invalid) == nil, "reject invalid or regressive begin")
            trace.end(token, sessionID: session, at: invalid)
            trace.finish(.failed, sessionID: session, at: invalid)
            let result = trace.snapshot(at: invalid)
            try require(
                result.elapsedSeconds == 2 && result.spans[0].state == .running, "bad clocks cannot damage trace")
            _ = try JSONEncoder().encode(result)
        }
        trace.end(token, sessionID: session, at: 15)
        try require(trace.snapshot(at: 14).elapsedSeconds == 5, "snapshot cannot regress behind an event")
        for invalid in [Double.nan, .infinity, -.infinity, -1] {
            let invalidOrigin = PlaybackStartupTrace(startedAt: invalid)
            let result = invalidOrigin.snapshot(at: .nan)
            try require(result.elapsedSeconds == 0, "bad origin must fall back to a finite monotonic start")
            _ = try JSONEncoder().encode(result)
        }
    }

    private static func serializationBoundary() throws {
        var trace = PlaybackStartupTrace(startedAt: 0)
        for (index, stage) in PlaybackStartupTrace.Stage.allCases.enumerated() {
            let token = trace.begin(stage, sessionID: trace.sessionID, at: Double(index))
            trace.end(token, sessionID: trace.sessionID, at: Double(index))
        }
        let end = Double(PlaybackStartupTrace.Stage.allCases.count)
        trace.finish(.receiverMediaRequest, sessionID: trace.sessionID, at: end)
        let snapshot = trace.snapshot(at: end)
        let data = try JSONEncoder().encode(snapshot)
        try require(
            try JSONDecoder().decode(PlaybackStartupTrace.Snapshot.self, from: data) == snapshot, "snapshot round trip")
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        try require(
            Set(object?.keys.map { $0 } ?? []) == [
                "sessionID", "startedAtUptimeSeconds", "elapsedSeconds", "outcome", "spans",
            ], "fixed private export schema")
        let spans = object?["spans"] as? [[String: Any]] ?? []
        try require(spans.count == PlaybackStartupTrace.Stage.allCases.count, "all measured stages can export")
        try require(
            spans.allSatisfy {
                Set($0.keys) == ["stage", "startSeconds", "elapsedSeconds", "state"]
            }, "relative stage timings only, no wall time or user metadata")
    }

    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw Failure(message: message) }
    }

    private struct Failure: Error, CustomStringConvertible {
        let message: String
        var description: String { message }
    }
}
