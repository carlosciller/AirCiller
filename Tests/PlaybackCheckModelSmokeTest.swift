import Foundation

@main
struct PlaybackCheckModelSmokeTest {
    static func main() throws {
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
            #"{"version":1,"deviceID":"test","clips":[{"path":"/a.mp4","route":"hls","externalSubtitle":"/a.sub"}]}"#,
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
