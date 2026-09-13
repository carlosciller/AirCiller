import Foundation

@main
struct PlaybackCheckModelSmokeTest {
    static func main() throws {
        try checkCachePlansAndEvidence()
        try expect(
            PlaybackCheckPlan.Profile.hlsCacheReuse.stableObservationSeconds == 8, "Cache windows last eight seconds")
        for profile: PlaybackCheckPlan.Profile in [
            .controls, .trackChanges, .cancelPreparation, .playlistTransition, .longPause, .cancelBitmap, .subtitleSeek,
        ] {
            try expect(profile.stableObservationSeconds == 5, "Other profiles retain five-second observation windows")
        }
        let seekPlan =
            #"{"version":1,"deviceID":"fixture","profile":"subtitleSeek","clips":[{"path":"/clip.m2ts","route":"hls","externalSubtitle":"/cue.srt"}]}"#
        _ = try PlaybackCheckPlan.decode(Data(seekPlan.utf8))
        try expectRejected(Data(seekPlan.replacingOccurrences(of: "\"hls\"", with: "\"directHDR\"").utf8))
        try expectRejected(Data(seekPlan.replacingOccurrences(of: ",\"externalSubtitle\":\"/cue.srt\"", with: "").utf8))
        for ext in ["ts", "MTS", "m2ts"] {
            _ = try PlaybackCheckPlan.decode(
                Data(
                    """
                    {"version":1,"deviceID":"fixture","clips":[{"path":"/clip.\(ext)","route":"hls"}]}
                    """.utf8))
        }
        let hdrHLS = #"{"version":1,"deviceID":"fixture","clips":[{"path":"/clip.m2ts","route":"hlsHDR"}]}"#
        _ = try PlaybackCheckPlan.decode(Data(hdrHLS.utf8))
        try expectRejected(
            Data(
                hdrHLS.replacingOccurrences(of: #""route":"hlsHDR""#, with: #""route":"hlsHDR","subtitleIndex":2"#).utf8
            ))
        try expectRejected(
            Data(
                hdrHLS.replacingOccurrences(
                    of: #""deviceID":"fixture""#, with: #""deviceID":"fixture","profile":"cancelBitmap""#
                ).utf8))
        // Hardware trace: HLS reported paused immediately after playing. The
        // former toggle sent resume while the test was waiting for pause.
        for initiallyPlaying in [false, true] {
            var receiverPlaying = initiallyPlaying
            var commands: [String] = []
            let pause = {
                commands.append("pause")
                receiverPlaying = false
                return true
            }
            let resume = {
                commands.append("resume")
                receiverPlaying = true
                return true
            }
            try expect(PlaybackCheckControl.request(playing: false, pause: pause, resume: resume), "Send pause")
            try expect(!receiverPlaying && commands == ["pause"], "Pause never toggles an already-paused receiver")
            try expect(PlaybackCheckControl.request(playing: true, pause: pause, resume: resume), "Send resume")
            try expect(receiverPlaying && commands == ["pause", "resume"], "Resume requests an explicit state")
        }
        try expect(
            !PlaybackCheckControl.request(playing: false, pause: { false }, resume: { true }),
            "A failed pause is not retried as resume")
        try expect(
            !PlaybackCheckControl.request(playing: true, pause: { true }, resume: { false }),
            "A failed resume is not retried as pause")
        let playing = event(0, "playing", position: 5, playing: true)
        let progress = event(2, "status", position: 7, playing: true)
        try expect(PlaybackCheckEvidence.hasProgress([playing, progress][...]), "Receiver progress")
        try expect(
            PlaybackCheckEvidence.hasProgress(
                [playing, event(3, "paused", source: "receiver", position: 8)][...]),
            "Pause reports establish progress without a periodic status feed")
        try expect(
            !PlaybackCheckEvidence.hasProgress(
                [event(0, "paused", source: "receiver", position: 5), progress][...]),
            "A paused baseline does not prove a playing interval")
        try expect(!PlaybackCheckEvidence.hasProgress([playing][...]), "A single start is insufficient")
        try expect(
            PlaybackCheckEvidence.progressVerdict([playing, event(3, "paused", source: "receiver")][...]) == .missing,
            "A state-only receiver leaves position unverified")
        // Shape observed on hardware: paused has no position; resumed reports it.
        let resumeTrace = [
            event(1.50, "playing", position: 0, playing: true),
            event(4.70, "paused", source: "receiver"),
            event(4.80, "resumed", source: "receiver", position: 2.94),
        ]
        try expect(
            PlaybackCheckEvidence.progressVerdict(resumeTrace[...]) == .confirmed,
            "Receiver position on resume confirms the preceding playback interval")
        try expect(
            PlaybackCheckEvidence.progressVerdict(
                [resumeTrace[0], resumeTrace[1], event(4.80, "resumed", source: "command", position: 2.94)][...])
                == .missing,
            "A local resume acknowledgement cannot replace the receiver's position")
        try expect(
            PlaybackCheckEvidence.progressVerdict(
                [playing, event(3, "paused", source: "receiver", position: 5)][...]) == .mismatch,
            "A supplied but frozen receiver position remains a failure")
        try expect(!PlaybackCheckEvidence.hasProgress([playing, playing][...]), "Duplicate events")
        try expect(
            !PlaybackCheckEvidence.hasProgress([playing, event(2, "status", position: 35, playing: true)][...]),
            "A seek is not playback progress")
        try expect(
            !PlaybackCheckEvidence.hasProgress([event(0, "resumed", source: "command"), progress][...]),
            "Command acceptance is not receiver progress")
        try expect(
            !PlaybackCheckEvidence.paused([event(1, "paused", source: "command")][...]),
            "Pause acknowledgement is not receiver state")
        try expect(
            PlaybackCheckEvidence.paused([event(1, "paused", source: "receiver")][...]),
            "Receiver pause")
        try expect(
            !PlaybackCheckEvidence.paused([event(1, "paused", source: "receiver"), progress][...]),
            "Later receiver state supersedes pause")

        let acknowledgement = event(3, "seeked", position: 15, requestID: UUID().uuidString)
        let pausedPosition = event(4, "status", position: 15, playing: false)
        try expect(
            PlaybackCheckEvidence.seekCommandsAcknowledged([acknowledgement][...], target: 15, count: 1),
            "Separate command acceptance")
        try expect(
            PlaybackCheckEvidence.seekVerdict([acknowledgement][...], target: 15, count: 1) == .missing,
            "Acknowledged seek without a receiver position is unverified")
        try expect(
            PlaybackCheckEvidence.seekVerdict(
                [acknowledgement, event(4, "resumed", source: "receiver", position: 25)][...], target: 15, count: 1)
                == .mismatch, "A wrong reported destination remains a failure")
        try expect(
            PlaybackCheckEvidence.settledSeek([acknowledgement, pausedPosition][...], target: 15, count: 1),
            "Seek confirmed by receiver")
        try expect(
            !PlaybackCheckEvidence.settledSeek([acknowledgement][...], target: 15, count: 1),
            "Seek command acceptance alone")
        try expect(
            !PlaybackCheckEvidence.settledSeek(
                [event(2, "status", position: 15, playing: false), acknowledgement][...], target: 15, count: 1),
            "Old receiver position cannot confirm a later command")
        try expect(
            !PlaybackCheckEvidence.settledSeek(
                [acknowledgement, acknowledgement, pausedPosition][...], target: 15, count: 2),
            "Duplicate acknowledgement IDs")
        try expect(
            !PlaybackCheckEvidence.settledSeek(
                [acknowledgement, event(4, "status", position: 25, playing: false)][...], target: 15, count: 1),
            "A wrong receiver position fails")

        try expect(PlaybackCheckEvent(seconds: 0, kind: "paired") == nil, "Credential events excluded")
        try expect(event(0, "stopped").origin == .helper, "Local stop is not receiver proof")
        let invalid = event(0, "status", position: .nan, duration: .infinity, requestID: "/private/media")
        try expect(invalid.position == nil && invalid.duration == nil && invalid.requestID == nil, "Invalid fields")
        try expect(PlaybackCheckEvent(seconds: .nan, kind: "status") == nil, "Invalid clock")
        try expect(
            PlaybackCheckEvidence.resumedAt([event(1, "playing", position: 12)][...], target: 12) == .confirmed,
            "Track restart retains position")
        try expect(
            PlaybackCheckEvidence.resumedAt([event(1, "resumed", source: "command", position: 12)][...], target: 12)
                == .missing, "A command is not a restart position")
        try expect(
            PlaybackCheckEvidence.resumedAt([event(1, "playing", position: 0)][...], target: 12) == .mismatch,
            "Restarting at zero loses position")
        let transition = [event(0, "playing", position: 0), event(6, "ended"), event(8, "playing", position: 0)]
        try expect(
            PlaybackCheckEvidence.singlePlaylistTransition(loads: [1, 2], events: transition[...]),
            "Natural end starts exactly one next item")
        try expect(
            !PlaybackCheckEvidence.singlePlaylistTransition(loads: [1, 2, 2], events: transition[...]),
            "Repeated next load fails")
        try expect(
            !PlaybackCheckEvidence.singlePlaylistTransition(
                loads: [1, 2], events: [transition[0], transition[2]][...]),
            "Manual transition is not natural completion")

        let valid = Data(
            #"{"version":1,"deviceID":"test-device","clips":[{"path":"/fixtures/test.mp4","route":"hls"}]}"#.utf8)
        let plan = try PlaybackCheckPlan.decode(valid)
        try expect(plan.clips.count == 1, "Minimal plan")
        try expect(plan.selectedProfile == .controls, "Existing plans retain the basic control profile")
        let externalPGS = try PlaybackCheckPlan.decode(
            Data(
                #"{"version":1,"deviceID":"test","clips":[{"path":"/a.mp4","route":"directHDR","externalSubtitle":"/a.sup"}]}"#
                    .utf8))
        try expect(externalPGS.clips[0].externalSubtitle == "/a.sup", "External PGS uses the normal attachment action")
        for ext in ["idx", "sub", "IDX"] {
            let vobsub = try PlaybackCheckPlan.decode(
                Data(
                    "{\"version\":1,\"deviceID\":\"test\",\"clips\":[{\"path\":\"/a.mp4\",\"route\":\"hls\",\"externalSubtitle\":\"/a.\(ext)\"}]}"
                        .utf8))
            try expect(vobsub.clips[0].externalSubtitle == "/a.\(ext)", "Either VobSub half is accepted by the plan")
        }
        let changes = try PlaybackCheckPlan.decode(
            Data(
                #"{"version":1,"deviceID":"test","profile":"trackChanges","clips":[{"path":"/a.mp4","route":"directHDR","externalSubtitle":"/a.srt","alternateSubtitle":"/b.srt"}]}"#
                    .utf8))
        try expect(changes.selectedProfile == .trackChanges, "Explicit track scenario")
        let pausePlan = try PlaybackCheckPlan.decode(
            Data(
                #"{"version":1,"deviceID":"test","profile":"longPause","clips":[{"path":"/a.mp4","route":"hls","externalSubtitle":"/a.srt"}]}"#
                    .utf8))
        try expect(pausePlan.selectedProfile == .longPause, "Long pause is opt-in")
        let bitmapPlan =
            #"{"version":1,"deviceID":"local-only","profile":"cancelBitmap","clips":[{"path":"/a.mkv","route":"hls","subtitleIndex":2},{"path":"/b.mkv","route":"directHDR","subtitleIndex":2}]}"#
        try expect(
            try PlaybackCheckPlan.decode(Data(bitmapPlan.utf8)).selectedProfile == .cancelBitmap,
            "Bitmap cancellation has a separate local-only profile")
        try expectRejected(Data(bitmapPlan.replacingOccurrences(of: "local-only", with: "receiver").utf8))
        try expectRejected(
            Data(bitmapPlan.replacingOccurrences(of: "\"subtitleIndex\":2", with: "\"subtitleIndex\":null").utf8))
        try expectRejected(Data(bitmapPlan.replacingOccurrences(of: "/b.mkv", with: "/a.mkv").utf8))
        try expect(plan.captureReadyFile == nil, "Capture coordination is optional")
        let capturePlan = try PlaybackCheckPlan.decode(
            Data(
                #"{"version":1,"deviceID":"test-device","captureReadyFile":"/fixtures/session.ready","clips":[{"path":"/fixtures/test.mp4","route":"hls"}]}"#
                    .utf8))
        try expect(capturePlan.captureReadyFile == "/fixtures/session.ready", "Explicit capture-ready marker")
        try expect(
            PlaybackCheckFailure.timedOut.outcome == "inconclusive", "Missing evidence is not a playback verdict")
        for text in [
            #"{"version":2,"deviceID":"test","clips":[]}"#,
            #"{"version":1,"deviceID":"","clips":[{"path":"/a.mp4","route":"hls"}]}"#,
            #"{"version":1,"deviceID":"test","clips":[{"path":"relative.mp4","route":"hls"}]}"#,
            #"{"version":1,"deviceID":"test","captureReadyFile":"relative.ready","clips":[{"path":"/a.mp4","route":"hls"}]}"#,
            #"{"version":1,"deviceID":"test","captureReadyFile":"/fixtures/session.mp4","clips":[{"path":"/a.mp4","route":"hls"}]}"#,
            #"{"version":1,"deviceID":"test","clips":[{"path":"/a.mp4","route":"directHDR"}]}"#,
            #"{"version":1,"deviceID":"test","clips":[{"path":"/a.mp4","route":"hls","subtitleIndex":-1}]}"#,
            #"{"version":1,"deviceID":"test","clips":[{"path":"/a.mp4","route":"hls","externalSubtitle":"/a.exe"}]}"#,
            #"{"version":1,"deviceID":"test","clips":[{"path":"/a.mp4","route":"hls","subtitleIndex":2,"externalSubtitle":"/a.srt"}]}"#,
            #"{"version":1,"deviceID":"test","profile":"trackChanges","clips":[{"path":"/a.mp4","route":"hls","externalSubtitle":"/a.srt"}]}"#,
            #"{"version":1,"deviceID":"test","profile":"cancelPreparation","captureReadyFile":"/a.ready","clips":[{"path":"/a.mp4","route":"hls"}]}"#,
            #"{"version":1,"deviceID":"test","profile":"playlistTransition","clips":[{"path":"/a.mp4","route":"directHDR","externalSubtitle":"/a.srt","nextClip":{"path":"/a.mp4","route":"hls"}}]}"#,
            #"{"version":1,"deviceID":"test","clips":[{"path":"/a.mp4","route":"hls","alternateSubtitle":"/b.srt"}]}"#,
            "not JSON",
        ] {
            try expectRejected(Data(text.utf8))
        }
        try expectRejected(Data(repeating: 32, count: 65_537))

        let report = PlaybackCheckReport(appVersion: "test", outcome: "automated_checks_passed_output_unverified")
        let encoded = try JSONEncoder().encode(report)
        let object = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        try expect(object["outputVerification"] as? String == "not_observed", "Automation cannot mark audiovisual pass")
        try expect(!String(decoding: encoded, as: UTF8.self).contains(plan.deviceID), "Device excluded from report")
        print("Playback check evidence and plan safeguards: OK")
    }

    private static func checkCachePlansAndEvidence() throws {
        let controls = #"{"version":1,"deviceID":"fixture","clips":[{"path":"/clip.mkv","route":"hls"}]}"#
        try expect(
            try PlaybackCheckPlan.decode(Data(controls.utf8)).selectedHLSCacheMode == .disabled,
            "Ordinary checks never enable a production or isolated cache")
        let cold =
            #"{"version":1,"deviceID":"fixture","hlsCacheMode":"isolated","clips":[{"path":"/clip.mkv","route":"hls","expectedCacheHit":false}]}"#
        try expect(
            try PlaybackCheckPlan.decode(Data(cold.utf8)).clips[0].expectedCacheHit == false,
            "Explicit cold expectation")
        let reuse =
            #"{"version":1,"deviceID":"fixture","hlsCacheMode":"isolated","profile":"hlsCacheReuse","clips":[{"path":"/clip.mkv","route":"hls","externalSubtitle":"/a.srt","alternateSubtitle":"/b.srt"}]}"#
        try expect(
            try PlaybackCheckPlan.decode(Data(reuse.utf8)).selectedProfile == .hlsCacheReuse,
            "Reuse is explicitly isolated")
        for invalid in [
            cold.replacingOccurrences(of: ",\"hlsCacheMode\":\"isolated\"", with: ""),
            cold.replacingOccurrences(of: "isolated", with: "disabled"),
            cold.replacingOccurrences(of: "isolated", with: "production"),
            cold.replacingOccurrences(of: #""expectedCacheHit":false"#, with: #""expectedCacheHit":"false""#),
            reuse.replacingOccurrences(of: "isolated", with: "disabled"),
            reuse.replacingOccurrences(of: ",\"externalSubtitle\":\"/a.srt\"", with: ""),
            reuse.replacingOccurrences(of: ",\"alternateSubtitle\":\"/b.srt\"", with: ""),
            reuse.replacingOccurrences(of: #""route":"hls""#, with: #""route":"directHDR""#),
        ] { try expectRejected(Data(invalid.utf8)) }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "PlaybackCheck-Base-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["video-init.mp4", "video-00000.m4s", "audio-init.mp4", "audio-00000.m4s"] {
            try Data(name.utf8).write(to: root.appendingPathComponent(name))
        }
        let original = try PlaybackCheckBaseFingerprint.read(directory: root)
        try Data("mutable playlist".utf8).write(to: root.appendingPathComponent("master.m3u8"))
        try Data("new subtitle".utf8).write(to: root.appendingPathComponent("subtitle-00000.vtt"))
        try expect(
            try PlaybackCheckBaseFingerprint.read(directory: root) == original, "Only immutable base bytes compared")
        try Data("changed base".utf8).write(to: root.appendingPathComponent("audio-00000.m4s"))
        let changed = try PlaybackCheckBaseFingerprint.read(directory: root)
        try expect(changed != original, "Changed audio bytes cannot masquerade as warm reuse")

        func evidence(
            hit: Bool, expected: Bool?, base: PlaybackCheckBaseFingerprint?, packaging: Bool,
            lookup: Bool = true, receiver: Bool = true, requestedAt: Double = 9
        ) -> PlaybackCheckStartupEvidence {
            let completed = PlaybackStartupTrace.SpanState.completed
            var spans: [PlaybackStartupTrace.Span] = []
            if lookup {
                spans.append(.init(stage: .cacheLookup, startSeconds: 0, elapsedSeconds: 0.1, state: completed))
            }
            if packaging {
                spans.append(.init(stage: .packaging, startSeconds: 0.1, elapsedSeconds: 0.4, state: completed))
            }
            if receiver {
                spans.append(.init(stage: .receiverRequest, startSeconds: 0.5, elapsedSeconds: 0.5, state: completed))
            }
            return PlaybackCheckStartupEvidence(
                label: "fixture", requestedAtUptime: requestedAt, receiverConfirmedAtUptime: 11.1,
                cacheHit: hit,
                snapshot: .init(
                    sessionID: UUID(), startedAtUptimeSeconds: 10, elapsedSeconds: 1,
                    outcome: receiver ? .receiverMediaRequest : .prepared, spans: spans),
                expectedCacheHit: expected, baseFingerprint: base)
        }
        let warm = evidence(hit: true, expected: true, base: original, packaging: false)
        try warm.validate(sameBaseAs: original)
        try evidence(hit: false, expected: false, base: changed, packaging: true).validate(differentBaseFrom: original)
        func rejected(_ body: () throws -> Void) throws {
            do { try body() } catch PlaybackCheckFailure.cacheMismatch { return }
            throw NSError(domain: "PlaybackChecks.AcceptedWrongCacheEvidence", code: 1)
        }
        try rejected { try evidence(hit: false, expected: true, base: original, packaging: true).validate() }
        try rejected { try evidence(hit: true, expected: false, base: original, packaging: false).validate() }
        try rejected { try evidence(hit: true, expected: true, base: nil, packaging: false).validate() }
        try rejected { try evidence(hit: true, expected: true, base: original, packaging: true).validate() }
        try rejected { try evidence(hit: false, expected: false, base: original, packaging: false).validate() }
        try rejected {
            try evidence(hit: true, expected: true, base: original, packaging: false, lookup: false).validate()
        }
        try rejected {
            try evidence(hit: true, expected: true, base: original, packaging: false, receiver: false).validate()
        }
        try rejected {
            try evidence(hit: true, expected: true, base: original, packaging: false, requestedAt: 10.5).validate()
        }
        try rejected { try warm.validate(sameBaseAs: changed) }
        try rejected { try warm.validate(differentBaseFrom: original) }
        let encoded = String(decoding: try JSONEncoder().encode(warm), as: UTF8.self)
        try expect(!encoded.contains(root.path), "Startup and base evidence excludes fixture paths")
    }

    private static func event(
        _ seconds: Double, _ kind: String, source: String? = nil, position: Double? = nil,
        duration: Double? = nil, playing: Bool? = nil, requestID: String? = nil
    ) -> PlaybackCheckEvent {
        PlaybackCheckEvent(
            seconds: seconds, kind: kind, source: source, position: position, duration: duration,
            playing: playing, requestID: requestID)!
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "PlaybackChecks.\(message)", code: 1) }
    }

    private static func expectRejected(_ data: Data) throws {
        do { _ = try PlaybackCheckPlan.decode(data) } catch PlaybackCheckFailure.invalidPlan { return }
        throw NSError(domain: "PlaybackChecks.AcceptedInvalidPlan", code: 1)
    }
}
