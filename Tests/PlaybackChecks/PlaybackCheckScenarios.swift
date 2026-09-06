import Foundation

// Opt-in scenarios drive ordinary coordinator actions. No playback packager is replaced.
@MainActor
final class PlaybackCheckScenarioRunner {
    private let coordinator: StreamCoordinator
    private var events: [PlaybackCheckEvent] = []
    private var loads: [Int] = []
    private var overflowed = false
    private let began = ProcessInfo.processInfo.systemUptime
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    private var step = "scenario_setup" {
        didSet {
            print("Checking: \(step)")
            fflush(nil)
        }
    }

    init(coordinator: StreamCoordinator) { self.coordinator = coordinator }

    func run(_ clip: PlaybackCheckPlan.Clip, profile: PlaybackCheckPlan.Profile) async -> PlaybackCheckResult {
        var result = PlaybackCheckResult(clip: 1, route: clip.route, subtitlesRequested: clip.externalSubtitle != nil)
        result.startedAtUptime = began
        result.profile = profile
        coordinator.airPlay.onPlaybackCheckEvent = { [weak self] kind, source, position, duration, playing, id in
            guard let self,
                let event = PlaybackCheckEvent(
                    seconds: self.now - self.began, kind: kind, source: source, position: position,
                    duration: duration, playing: playing, requestID: id)
            else { return }
            guard self.events.count < 4_096 else {
                self.overflowed = true
                return
            }
            self.events.append(event)
        }
        coordinator.onPlaybackCheckLoad = { [weak self] url in
            guard let self else { return }
            guard self.loads.count < 16 else {
                self.overflowed = true
                return
            }
            self.loads.append(url.path == clip.path ? 1 : (url.path == clip.nextClip?.path ? 2 : 0))
        }
        defer {
            coordinator.onPlaybackCheckLoad = nil
            coordinator.airPlay.onPlaybackCheckEvent = nil
        }
        var directories: Set<URL> = []
        do {
            step = "analysis"
            coordinator.clearQueue()
            if let next = clip.nextClip {
                coordinator.handleURLs([URL(fileURLWithPath: clip.path), URL(fileURLWithPath: next.path)])
            } else {
                coordinator.loadVideo(URL(fileURLWithPath: clip.path), autoStart: false, startingAt: 0)
            }
            try await wait(seconds: 40) { self.coordinator.probeInfo != nil && self.coordinator.network.isReady }
            guard let probe = coordinator.probeInfo, (45...180).contains(probe.duration),
                ["h264", "hevc"].contains(probe.videoCodec.lowercased()),
                coordinator.selectedAudio?.canPassThrough == true,
                clip.route == .directHDR ? probe.isHDR : !probe.isHDR
            else { throw PlaybackCheckFailure.unsupportedFixture }
            coordinator.selectedSubtitleID = nil
            if let path = clip.externalSubtitle,
                let subtitle = coordinator.registerExternalSubtitle(URL(fileURLWithPath: path))
            {
                coordinator.selectedSubtitleID = subtitle.id
            }
            coordinator.audioOutputMode = .original
            if profile == .trackChanges, clip.route == .hls {
                guard coordinator.audioTracks.count == 2, coordinator.audioTracks.allSatisfy(\.canPassThrough) else {
                    throw PlaybackCheckFailure.unsupportedFixture
                }
                coordinator.selectedAudioID = coordinator.audioTracks[0].id
            }
            result.completedSteps.append(step)
            step = profile == .cancelPreparation ? "observe_running_preparation" : "start_and_media_request"
            let marker = events.count
            coordinator.start(at: 0)
            if profile == .cancelPreparation {
                try await cancelPreparation(result: &result, directories: &directories)
            } else {
                try await started(after: marker, route: clip.route, expectedPosition: 0, result: &result)
                if let directory = coordinator.activePreparedDirectory { directories.insert(directory) }
                result.completedSteps.append(step)
                try await observe("initial", after: marker, result: &result)
                if profile == .trackChanges {
                    try await changeTracks(clip, result: &result, directories: &directories)
                } else if profile == .playlistTransition {
                    try await finishPlaylist(clip, result: &result, directories: &directories)
                } else if profile == .longPause {
                    try await longPause(result: &result)
                } else {
                    throw PlaybackCheckFailure.invalidPlan
                }
            }
        } catch {
            result.failure = (error as? PlaybackCheckFailure) ?? (Task.isCancelled ? .interrupted : .applicationError)
            result.failedStep = step
        }
        if let directory = coordinator.activePreparedDirectory { directories.insert(directory) }
        coordinator.stop()
        let deadline = now + 8
        while !coordinator.playbackCheckRuntimeIsIdle, now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        result.cleanupConfirmed =
            coordinator.playbackCheckRuntimeIsIdle
            && directories.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }
        if result.cleanupConfirmed {
            result.completedSteps.append("stop_and_cleanup")
        } else {
            result.failure = .cleanupFailed
            result.failedStep = "stop_and_cleanup"
        }
        result.loadSequence = loads
        result.events = events
        result.elapsedSeconds = now - began
        return result
    }

    private func started(
        after marker: Int, route: PlaybackCheckPlan.Route, expectedPosition: Double,
        result: inout PlaybackCheckResult, allowEnd: Bool = false
    ) async throws {
        try await wait(seconds: 70, after: marker, allowStopped: true, allowEnd: allowEnd) {
            self.coordinator.isStreaming && self.coordinator.isPlaying
                && self.coordinator.streamTelemetry.hasConfirmedMediaRequest
                && self.events[marker...].contains { $0.kind == "playing" && $0.origin == .receiver }
        }
        guard let directory = coordinator.activePreparedDirectory,
            FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(route == .directHDR ? "movie.mp4" : "master.m3u8").path),
            coordinator.audioOutputMode == .original, coordinator.selectedAudio?.canPassThrough == true
        else {
            throw PlaybackCheckFailure.unsupportedFixture
        }
        switch PlaybackCheckEvidence.resumedAt(events[marker...], target: expectedPosition) {
        case .confirmed: result.completedSteps.append("\(step)_receiver_position")
        case .missing: result.unverifiedChecks.append("\(step)_receiver_position")
        case .mismatch: throw PlaybackCheckFailure.receiverMismatch
        }
    }

    private func observe(_ label: String, after marker: Int, result: inout PlaybackCheckResult) async throws {
        let start = now
        try await wait(seconds: 7, after: marker, allowStopped: true) { self.now - start >= 5 }
        guard coordinator.isPlaying, coordinator.isStreaming else { throw PlaybackCheckFailure.receiverMismatch }
        result.outputWindows.append(PlaybackCheckOutputWindow(label: label, startedAtUptime: start, endedAtUptime: now))
    }

    private func changeTracks(
        _ clip: PlaybackCheckPlan.Clip, result: inout PlaybackCheckResult,
        directories: inout Set<URL>
    ) async throws {
        guard let path = clip.alternateSubtitle,
            let alternate = coordinator.registerExternalSubtitle(URL(fileURLWithPath: path))
        else {
            throw PlaybackCheckFailure.unsupportedFixture
        }
        coordinator.selectedSubtitleID = alternate.id
        try await applyChange("subtitleChanged", route: clip.route, result: &result, directories: &directories)
        if clip.route == .hls {
            coordinator.selectedAudioID = coordinator.audioTracks[1].id
            try await applyChange("audioChanged", route: clip.route, result: &result, directories: &directories)
            coordinator.selectedSubtitleID = nil
            try await applyChange("subtitlesOff", route: clip.route, result: &result, directories: &directories)
        }
    }

    private func applyChange(
        _ label: String, route: PlaybackCheckPlan.Route, result: inout PlaybackCheckResult,
        directories: inout Set<URL>
    ) async throws {
        step = label
        let target = coordinator.currentTime
        let previous = coordinator.activePreparedDirectory
        let marker = events.count
        coordinator.applyTrackSettings()
        try await started(after: marker, route: route, expectedPosition: target, result: &result)
        guard let directory = coordinator.activePreparedDirectory, directory != previous else {
            throw PlaybackCheckFailure.receiverMismatch
        }
        directories.insert(directory)
        result.completedSteps.append(label)
        try await observe(label, after: marker, result: &result)
    }

    private func cancelPreparation(result: inout PlaybackCheckResult, directories: inout Set<URL>) async throws {
        // Poll the real FFmpeg process. A preparation that already finished is not a cancellation pass.
        try await wait(seconds: 15, pollMilliseconds: 10) {
            self.coordinator.isPreparing && self.coordinator.playbackCheckPreparationProcessIsRunning
        }
        guard !coordinator.isStreaming, !events.contains(where: { $0.kind == "playing" }) else {
            throw PlaybackCheckFailure.receiverMismatch
        }
        if let directory = coordinator.activePreparedDirectory { directories.insert(directory) }
        result.completedSteps.append("running_preparation_observed")
        step = "cancel_preparation"
        coordinator.stop()
        let stoppedAt = now
        try await wait(seconds: 8, allowStopped: true) { self.coordinator.playbackCheckRuntimeIsIdle }
        result.completedSteps.append("preparation_cancelled")
        try await wait(seconds: 5, allowStopped: true) { self.now - stoppedAt >= 3 }
        guard coordinator.playbackCheckRuntimeIsIdle,
            !events.contains(where: { $0.kind == "playing" || $0.receiverIsPlaying == true }),
            !coordinator.streamTelemetry.hasConfirmedMediaRequest
        else { throw PlaybackCheckFailure.receiverMismatch }
        result.completedSteps.append("no_delayed_playback_after_stop")
    }

    private func longPause(result: inout PlaybackCheckResult) async throws {
        step = "pause_before_long_wait"
        let directory = coordinator.activePreparedDirectory
        let pauseMarker = events.count
        guard coordinator.airPlay.pause() else { throw PlaybackCheckFailure.receiverMismatch }
        try await wait(seconds: 15, after: pauseMarker) {
            PlaybackCheckEvidence.paused(self.events[pauseMarker...]) && !self.coordinator.isPlaying
        }
        // Paused notifications may omit position. Establish a fixed paused seek;
        // its acknowledgement is not position proof until the receiver resumes.
        let position = 15.0
        let seekMarker = events.count
        coordinator.seek(to: position)
        try await wait(seconds: 15, after: pauseMarker) {
            PlaybackCheckEvidence.seekCommandsAcknowledged(self.events[seekMarker...], target: position, count: 1)
                && PlaybackCheckEvidence.paused(self.events[pauseMarker...]) && !self.coordinator.isPlaying
        }
        result.completedSteps.append("paused_seek_acknowledged")
        let pausedAt = now
        // The supervisor suspends sample persistence, not the approved input or identity guard.
        step = "hold_long_pause"
        try await wait(seconds: 365, after: pauseMarker) {
            guard self.coordinator.isStreaming, !self.coordinator.isPlaying,
                self.coordinator.activePreparedDirectory == directory,
                !self.events[pauseMarker...].contains(where: { $0.receiverIsPlaying == true })
            else { throw PlaybackCheckFailure.receiverMismatch }
            return self.now - pausedAt >= 360
        }
        result.pauseWindow = PlaybackCheckOutputWindow(
            label: "paused", startedAtUptime: pausedAt, endedAtUptime: now)
        result.completedSteps.append("six_minute_pause_same_session")
        step = "resume_after_long_pause"
        let resumeMarker = events.count
        guard coordinator.airPlay.resume() else { throw PlaybackCheckFailure.receiverMismatch }
        try await wait(seconds: 20, after: resumeMarker) {
            self.coordinator.isPlaying && self.events[resumeMarker...].contains { $0.receiverIsPlaying == true }
        }
        guard PlaybackCheckEvidence.resumedAt(events[resumeMarker...], target: position) == .confirmed,
            coordinator.activePreparedDirectory == directory, loads == [1]
        else { throw PlaybackCheckFailure.receiverMismatch }
        result.completedSteps.append("resume_same_position_without_reload")
        try await observe("afterPause", after: resumeMarker, result: &result)
    }

    private func finishPlaylist(
        _ clip: PlaybackCheckPlan.Clip, result: inout PlaybackCheckResult,
        directories: inout Set<URL>
    ) async throws {
        guard let next = clip.nextClip else { throw PlaybackCheckFailure.invalidPlan }
        step = "natural_end_after_tail_seek"
        let target = coordinator.duration - 6
        let marker = events.count
        coordinator.seek(to: target)
        try await wait(seconds: 12, after: marker) {
            PlaybackCheckEvidence.seekCommandsAcknowledged(self.events[marker...], target: target, count: 1)
        }
        try await wait(seconds: 35, after: marker, allowStopped: true, allowEnd: true) {
            self.coordinator.selectedURL?.path == next.path
                && self.events[marker...].contains { $0.kind == "ended" && $0.origin == .receiver }
        }
        result.completedSteps.append(step)
        step = "automatic_next_item"
        let nextMarker = events.firstIndex(where: { $0.kind == "ended" })!.advanced(by: 1)
        try await started(after: nextMarker, route: next.route, expectedPosition: 0, result: &result)
        if let directory = coordinator.activePreparedDirectory { directories.insert(directory) }
        guard coordinator.selectedSubtitleID == nil else { throw PlaybackCheckFailure.receiverMismatch }
        try await observe("nextItem", after: nextMarker, result: &result)
        guard PlaybackCheckEvidence.singlePlaylistTransition(loads: loads, events: events[...]),
            coordinator.queueItems.map(\.path) == [clip.path, next.path]
        else { throw PlaybackCheckFailure.receiverMismatch }
        result.completedSteps.append("exactly_one_playlist_transition")
    }

    private func wait(
        seconds: Double, after marker: Int = 0, allowStopped: Bool = false,
        allowEnd: Bool = false, pollMilliseconds: Int64 = 100, until condition: () throws -> Bool
    ) async throws {
        let deadline = now + seconds
        while true {
            try Task.checkCancellation()
            if coordinator.airPlay.isPairingPresented { throw PlaybackCheckFailure.authorizationUnavailable }
            if coordinator.showConversionAlert { throw PlaybackCheckFailure.conversionRequested }
            if coordinator.hasError { throw PlaybackCheckFailure.applicationError }
            if overflowed { throw PlaybackCheckFailure.evidenceLimit }
            if events[marker...].contains(where: {
                $0.kind == "error" || (!allowStopped && $0.kind == "stopped") || (!allowEnd && $0.kind == "ended")
            }) {
                throw PlaybackCheckFailure.unexpectedTerminalEvent
            }
            if try condition() { return }
            guard now < deadline else { throw PlaybackCheckFailure.timedOut }
            try await Task.sleep(for: .milliseconds(pollMilliseconds))
        }
    }
}
