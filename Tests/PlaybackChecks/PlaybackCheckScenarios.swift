import Foundation

// Opt-in scenarios drive ordinary coordinator actions. No playback packager is replaced.
@MainActor
final class PlaybackCheckScenarioRunner {
    private let coordinator: StreamCoordinator
    private var events: [PlaybackCheckEvent] = []
    private var loads: [Int] = []
    private var playlistPaths: [String] = []
    private var overflowed = false
    private var requestedAudioOutput: AudioOutputMode = .original
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
        playlistPaths = [clip.path] + [clip.nextClip?.path].compactMap { $0 }
        var seasonFixture: URL?
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
            self.loads.append(url.path == self.playlistPaths.first ? 1 : (url.path == self.playlistPaths.last ? 2 : 0))
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
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent(
                    "AirCillerSeasonCheck-\(UUID()).mkv")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                seasonFixture = folder
                let firstURL = folder.appendingPathComponent(
                    "Episode 1." + URL(fileURLWithPath: clip.path).pathExtension)
                let nextURL = folder.appendingPathComponent(
                    "Episode 2." + URL(fileURLWithPath: next.path).pathExtension)
                try FileManager.default.copyItem(at: URL(fileURLWithPath: clip.path), to: firstURL)
                try FileManager.default.copyItem(at: URL(fileURLWithPath: next.path), to: nextURL)
                playlistPaths = [firstURL.path, nextURL.path]
                coordinator.handleURLs([folder], analyzeFirst: false)
                try await wait(seconds: 40) { !self.coordinator.isImportingLibrary }
                guard coordinator.queueItems.map(\.path) == playlistPaths,
                    coordinator.queueItems.allSatisfy({ $0.seasonID == folder.path })
                else { throw PlaybackCheckFailure.applicationError }
                result.completedSteps.append("season_folder_imported")
                coordinator.loadVideo(firstURL, autoStart: false)
            } else {
                coordinator.loadVideo(URL(fileURLWithPath: clip.path), autoStart: false, startingAt: 0)
            }
            try await wait(seconds: 40) { self.coordinator.probeInfo != nil && self.coordinator.network.isReady }
            guard let probe = coordinator.probeInfo, (45...180).contains(probe.duration),
                ["h264", "hevc"].contains(probe.videoCodec.lowercased()),
                clip.audioOutput == .losslessFLAC
                    ? coordinator.selectedAudio?.canPrepareLosslessFLAC == true
                    : (clip.audioOutput == .compatible
                        ? coordinator.selectedAudio?.canPassThrough == false
                        : coordinator.selectedAudio?.canPassThrough == true),
                clip.route == .directHDR ? probe.isHDR : !probe.isHDR
            else { throw PlaybackCheckFailure.unsupportedFixture }
            coordinator.selectedSubtitleID = nil
            if let path = clip.externalSubtitle,
                let subtitle = coordinator.registerExternalSubtitle(URL(fileURLWithPath: path))
            {
                coordinator.selectedSubtitleID = subtitle.id
            }
            requestedAudioOutput = clip.audioOutput == .losslessFLAC ? .losslessFLAC : .original
            coordinator.audioOutputMode = requestedAudioOutput
            if let delay = profile.fixedAudioDelay {
                guard (59.8...60.2).contains(probe.duration) else {
                    throw PlaybackCheckFailure.unsupportedFixture
                }
                coordinator.audioDelay = delay
                coordinator.subtitleDelay = 0
            }
            if [.trackChanges, .hlsCacheReuse].contains(profile), clip.route == .hls {
                guard coordinator.audioTracks.count == 2,
                    coordinator.audioTracks.allSatisfy({
                        requestedAudioOutput == .losslessFLAC ? $0.canPrepareLosslessFLAC : $0.canPassThrough
                    })
                else {
                    throw PlaybackCheckFailure.unsupportedFixture
                }
                coordinator.selectedAudioID = coordinator.audioTracks[0].id
            }
            result.completedSteps.append(step)
            step = profile == .cancelPreparation ? "observe_running_preparation" : "start_and_media_request"
            let marker = events.count
            let requestedAt = now
            coordinator.start(at: 0)
            if clip.audioOutput == .compatible {
                guard coordinator.showConversionAlert else { throw PlaybackCheckFailure.applicationError }
                coordinator.confirmAudioConversion()
                requestedAudioOutput = .compatible
                result.completedSteps.append("first_episode_audio_conversion_explicitly_approved")
            }
            if profile == .cancelPreparation {
                try await cancelPreparation(result: &result, directories: &directories)
            } else {
                try await started(after: marker, route: clip.route, expectedPosition: 0, result: &result)
                if let directory = coordinator.activePreparedDirectory { directories.insert(directory) }
                result.completedSteps.append(step)
                if profile == .playlistTransition, let seasonFixture, let next = clip.nextClip {
                    let extra = seasonFixture.appendingPathComponent(
                        "Episode import." + URL(fileURLWithPath: next.path).pathExtension)
                    try FileManager.default.copyItem(at: URL(fileURLWithPath: next.path), to: extra)
                    let current = coordinator.selectedURL
                    coordinator.handleURLs([seasonFixture], analyzeFirst: false)
                    try await wait(seconds: 15) { !self.coordinator.isImportingLibrary }
                    guard coordinator.selectedURL == current, coordinator.isStreaming, coordinator.isPlaying,
                        coordinator.airPlay.isSessionActive, loads == [1],
                        let imported = coordinator.queueItems.first(where: { $0.path == extra.path }),
                        imported.seasonID == seasonFixture.path
                    else { throw PlaybackCheckFailure.receiverMismatch }
                    coordinator.removeQueueItem(imported)
                    result.completedSteps.append("season_import_preserved_active_session")
                }
                let initialLabel = profile == .hlsCacheReuse ? "cold" : "initial"
                if clip.route == .hls {
                    try recordStartup(
                        initialLabel, requestedAt: requestedAt,
                        expectedCacheHit: profile == .hlsCacheReuse ? false : nil,
                        result: &result)
                }
                if let delay = profile.fixedAudioDelay {
                    try await checkAudioTiming(
                        delay: delay, requestedAt: requestedAt, after: marker,
                        result: &result, directories: &directories)
                } else {
                    try await observe(initialLabel, after: marker, result: &result)
                }
                if profile.fixedAudioDelay != nil {
                    // The timing scenario already observed its natural end.
                } else if profile == .trackChanges {
                    try await changeTracks(clip, result: &result, directories: &directories)
                } else if profile == .hlsCacheReuse {
                    try await checkCacheReuse(clip, result: &result, directories: &directories)
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
        coordinator.cancelLibraryImport()
        let deadline = now + 8
        while !coordinator.playbackCheckRuntimeIsIdle, now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if let seasonFixture { try? FileManager.default.removeItem(at: seasonFixture) }
        result.cleanupConfirmed =
            coordinator.playbackCheckRuntimeIsIdle
            && directories.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }
            && (seasonFixture.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true)
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
            coordinator.audioOutputMode == requestedAudioOutput,
            requestedAudioOutput == .losslessFLAC
                ? coordinator.selectedAudio?.canPrepareLosslessFLAC == true
                : (requestedAudioOutput == .compatible
                    ? coordinator.selectedAudio?.canPassThrough == false
                    : coordinator.selectedAudio?.canPassThrough == true)
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
        // Cache transitions need more sampling time on a busy capture source;
        // the offline frame, audio and cue requirements remain unchanged.
        let duration = result.profile.stableObservationSeconds(
            audioOutput: requestedAudioOutput == .losslessFLAC ? .losslessFLAC : .original)
        try await wait(seconds: duration + 2, after: marker, allowStopped: true) { self.now - start >= duration }
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

    private func checkAudioTiming(
        delay: Double, requestedAt: Double, after marker: Int, result: inout PlaybackCheckResult,
        directories: inout Set<URL>
    ) async throws {
        guard let directory = coordinator.activePreparedDirectory,
            let info = try HLSAudioTimelineInfo.load(directory: directory),
            abs(info.sourceDuration - 60) < 0.2,
            abs(coordinator.duration - info.presentationDuration) < 0.2
        else { throw PlaybackCheckFailure.unsupportedFixture }
        result.audioTiming = PlaybackCheckAudioTimingEvidence(
            requestedDelay: delay, sourceDuration: info.sourceDuration,
            presentationDuration: info.presentationDuration, videoContentOffset: info.videoContentOffset,
            playRequestedAtUptime: requestedAt)
        step = "audio_timing_opening"
        let opening = now
        try await wait(seconds: 15, after: marker, allowStopped: true) { self.now - opening >= 12 }
        result.outputWindows.append(
            PlaybackCheckOutputWindow(label: "initial", startedAtUptime: opening, endedAtUptime: now))
        guard coordinator.isStreaming, coordinator.isPlaying else { throw PlaybackCheckFailure.receiverMismatch }
        step = "audio_timing_pause"
        let pauseMarker = events.count
        guard coordinator.airPlay.pause() else { throw PlaybackCheckFailure.receiverMismatch }
        try await wait(seconds: 12, after: pauseMarker) {
            PlaybackCheckEvidence.paused(self.events[pauseMarker...]) && !self.coordinator.isPlaying
        }
        let pausedAt = now
        try await wait(seconds: 4, after: pauseMarker) {
            guard self.coordinator.isStreaming, !self.coordinator.isPlaying else {
                throw PlaybackCheckFailure.receiverMismatch
            }
            return self.now - pausedAt >= 2
        }
        result.completedSteps.append("audio_timing_pause_same_session")
        step = "audio_timing_seek_resume"
        let target = floor(15 + info.videoContentOffset)
        let seekMarker = events.count
        coordinator.seek(to: target)
        try await wait(seconds: 12, after: seekMarker) {
            PlaybackCheckEvidence.seekCommandsAcknowledged(self.events[seekMarker...], target: target, count: 1)
        }
        let resumeMarker = events.count
        guard coordinator.airPlay.resume() else { throw PlaybackCheckFailure.receiverMismatch }
        try await wait(seconds: 15, after: resumeMarker) {
            self.events[resumeMarker...].contains { $0.receiverIsPlaying == true && $0.position != nil }
        }
        guard PlaybackCheckEvidence.resumedAt(events[resumeMarker...], target: target) == .confirmed,
            coordinator.activePreparedDirectory == directory, loads == [1]
        else { throw PlaybackCheckFailure.receiverMismatch }
        try await observe("afterPause", after: resumeMarker, result: &result)
        result.completedSteps.append("audio_timing_seek_resume_same_session")
        if delay < 0 {
            try await checkAudioTimingTransitions(result: &result, directories: &directories)
        }
        step = "audio_timing_tail"
        let tailDirectory = coordinator.activePreparedDirectory
        let tailTarget = floor(info.presentationDuration - 9)
        let tailMarker = events.count
        coordinator.seek(to: tailTarget)
        try await wait(seconds: 12, after: tailMarker) {
            PlaybackCheckEvidence.seekCommandsAcknowledged(self.events[tailMarker...], target: tailTarget, count: 1)
        }
        // Request an explicit pause/resume to obtain an independent receiver
        // position. The seek acknowledgement alone cannot establish its target.
        guard coordinator.airPlay.pause() else { throw PlaybackCheckFailure.receiverMismatch }
        try await wait(seconds: 12, after: tailMarker) {
            PlaybackCheckEvidence.paused(self.events[tailMarker...]) && !self.coordinator.isPlaying
        }
        let tailResume = events.count
        guard coordinator.airPlay.resume() else { throw PlaybackCheckFailure.receiverMismatch }
        try await wait(seconds: 12, after: tailResume) {
            self.events[tailResume...].contains { $0.receiverIsPlaying == true && $0.position != nil }
        }
        guard let resumed = events[tailResume...].first(where: { $0.receiverIsPlaying == true && $0.position != nil }),
            let position = resumed.position, abs(position - tailTarget) <= 1,
            tailDirectory != nil, coordinator.activePreparedDirectory == tailDirectory
        else { throw PlaybackCheckFailure.receiverMismatch }
        result.audioTiming?.resumePosition = position
        result.audioTiming?.resumeEventSeconds = resumed.seconds
        try await wait(seconds: 18, after: tailResume, allowStopped: true, allowEnd: true) {
            self.events[tailResume...].contains { $0.kind == "ended" && $0.origin == .receiver }
        }
        let endings = events[tailResume...].filter { $0.kind == "ended" && $0.origin == .receiver }
        guard endings.count == 1, let ended = endings.first,
            ended.seconds - resumed.seconds >= info.presentationDuration - position - 1,
            ended.seconds - resumed.seconds <= info.presentationDuration - position + 4, loads == [1]
        else { throw PlaybackCheckFailure.receiverMismatch }
        result.audioTiming?.endEventSeconds = ended.seconds
        result.completedSteps.append("audio_timing_complete_tail")
        try await Task.sleep(for: .milliseconds(600))
    }

    private func checkAudioTimingTransitions(
        result: inout PlaybackCheckResult, directories: inout Set<URL>
    ) async throws {
        for (label, delay) in [("timingReplay", -5.0), ("timingDelayChanged", 5.0), ("timingAdvanceRestored", -5.0)] {
            step = label
            guard let previous = coordinator.activePreparedDirectory,
                let oldTimeline = try HLSAudioTimelineInfo.load(directory: previous)
            else { throw PlaybackCheckFailure.applicationError }
            let pauseMarker = events.count
            guard coordinator.airPlay.pause() else { throw PlaybackCheckFailure.receiverMismatch }
            try await wait(seconds: 12, after: pauseMarker) {
                PlaybackCheckEvidence.paused(self.events[pauseMarker...]) && !self.coordinator.isPlaying
            }
            // Independent oracle: receiver clock minus the old package's offset.
            // Do not use the coordinator's private mapping function here.
            let moviePosition = max(0, coordinator.currentTime - oldTimeline.videoContentOffset)
            var savedPosition: Double?
            var savedDuration: Double?
            if label == "timingReplay" {
                guard moviePosition > 5, moviePosition < oldTimeline.sourceDuration - 30 else {
                    throw PlaybackCheckFailure.receiverMismatch
                }
                coordinator.stop()
                let immediatePosition = coordinator.currentTime
                let immediateDuration = coordinator.duration
                try await wait(seconds: 8, allowStopped: true) { self.coordinator.playbackCheckRuntimeIsIdle }
                let saved = HistoryStore.loadRecent().first(where: { $0.path == coordinator.selectedURL?.path })
                let directoryRemoved = !FileManager.default.fileExists(atPath: previous.path)
                result.audioTiming?.stopCheckpoint = PlaybackCheckAudioTimingStopCheckpoint(
                    expectedMoviePosition: moviePosition, expectedMovieDuration: oldTimeline.sourceDuration,
                    immediatePosition: immediatePosition, immediateDuration: immediateDuration,
                    settledPosition: coordinator.currentTime, settledDuration: coordinator.duration,
                    directoryRemoved: directoryRemoved,
                    savedMoviePosition: saved?.lastPosition, savedMovieDuration: saved?.duration)
                step = "timingReplay_stop_directory"
                guard directoryRemoved else { throw PlaybackCheckFailure.receiverMismatch }
                step = "timingReplay_stop_position"
                guard abs(coordinator.currentTime - moviePosition) < 0.002 else {
                    throw PlaybackCheckFailure.receiverMismatch
                }
                step = "timingReplay_stop_duration"
                guard abs(coordinator.duration - oldTimeline.sourceDuration) < 0.002 else {
                    throw PlaybackCheckFailure.receiverMismatch
                }
                step = "timingReplay_stop_history_present"
                guard let saved else { throw PlaybackCheckFailure.receiverMismatch }
                step = "timingReplay_stop_history_position"
                guard abs(saved.lastPosition - moviePosition) < 0.002 else {
                    throw PlaybackCheckFailure.receiverMismatch
                }
                step = "timingReplay_stop_history_duration"
                guard abs(saved.duration - oldTimeline.sourceDuration) < 0.002 else {
                    throw PlaybackCheckFailure.receiverMismatch
                }
                savedPosition = saved.lastPosition
                savedDuration = saved.duration
                result.completedSteps.append("audio_timing_source_history_saved")
                step = label
            }
            coordinator.audioDelay = delay
            let marker = events.count
            if label == "timingReplay" {
                coordinator.start()
            } else {
                coordinator.applyTrackSettings()
            }
            // This fixture has a zero video origin; its small original audio
            // lead is verified separately against the actual package below.
            let expectedPosition = moviePosition + max(0, -delay)
            try await started(after: marker, route: .hls, expectedPosition: expectedPosition, result: &result)
            guard let directory = coordinator.activePreparedDirectory, directory != previous,
                let timeline = try HLSAudioTimelineInfo.load(directory: directory),
                abs(timeline.videoContentOffset - max(0, -delay)) < 0.05,
                let receiver = events[marker...].first(where: { $0.receiverIsPlaying == true && $0.position != nil }),
                let position = receiver.position
            else { throw PlaybackCheckFailure.receiverMismatch }
            directories.insert(directory)
            result.audioTiming?.transitions.append(
                PlaybackCheckAudioTimingTransition(
                    label: label, requestedDelay: delay, expectedMoviePosition: moviePosition,
                    expectedReceiverPosition: expectedPosition, receiverPosition: position,
                    receiverEventSeconds: receiver.seconds, videoContentOffset: timeline.videoContentOffset,
                    savedMoviePosition: savedPosition, savedMovieDuration: savedDuration))
            try await observe(label, after: marker, result: &result)
            result.completedSteps.append(label)
        }
    }

    private func applyChange(
        _ label: String, route: PlaybackCheckPlan.Route, result: inout PlaybackCheckResult,
        directories: inout Set<URL>, expectedCacheHit: Bool? = nil,
        sameBaseAs: PlaybackCheckBaseFingerprint? = nil, differentBaseFrom: PlaybackCheckBaseFingerprint? = nil
    ) async throws {
        step = label
        let target = coordinator.currentTime
        let previous = coordinator.activePreparedDirectory
        let marker = events.count
        let requestedAt = now
        coordinator.applyTrackSettings()
        try await started(after: marker, route: route, expectedPosition: target, result: &result)
        guard let directory = coordinator.activePreparedDirectory, directory != previous else {
            throw PlaybackCheckFailure.receiverMismatch
        }
        directories.insert(directory)
        result.completedSteps.append(label)
        if route == .hls {
            try recordStartup(
                label, requestedAt: requestedAt, expectedCacheHit: expectedCacheHit,
                sameBaseAs: sameBaseAs, differentBaseFrom: differentBaseFrom, result: &result)
        }
        try await observe(label, after: marker, result: &result)
    }

    private func recordStartup(
        _ label: String, requestedAt: Double, expectedCacheHit: Bool? = nil,
        sameBaseAs: PlaybackCheckBaseFingerprint? = nil, differentBaseFrom: PlaybackCheckBaseFingerprint? = nil,
        result: inout PlaybackCheckResult
    ) throws {
        let evidence = try PlaybackCheckStartupRecorder.record(
            coordinator: coordinator, label: label, requestedAtUptime: requestedAt,
            expectedCacheHit: expectedCacheHit)
        guard !result.startups.contains(where: { $0.snapshot.sessionID == evidence.snapshot.sessionID }) else {
            throw PlaybackCheckFailure.cacheMismatch
        }
        result.startups.append(evidence)
        try evidence.validate(sameBaseAs: sameBaseAs, differentBaseFrom: differentBaseFrom)
    }

    private func checkCacheReuse(
        _ clip: PlaybackCheckPlan.Clip, result: inout PlaybackCheckResult, directories: inout Set<URL>
    ) async throws {
        guard let original = result.startups.first?.baseFingerprint,
            let alternatePath = clip.alternateSubtitle,
            let alternate = coordinator.registerExternalSubtitle(URL(fileURLWithPath: alternatePath))
        else { throw PlaybackCheckFailure.unsupportedFixture }

        step = "warmReplay"
        let previous = coordinator.activePreparedDirectory
        coordinator.stop()
        try await wait(seconds: 8, allowStopped: true) { self.coordinator.playbackCheckRuntimeIsIdle }
        guard previous.map({ !FileManager.default.fileExists(atPath: $0.path) }) == true else {
            throw PlaybackCheckFailure.cleanupFailed
        }
        let marker = events.count
        let requestedAt = now
        coordinator.start(at: 0)
        try await started(after: marker, route: .hls, expectedPosition: 0, result: &result)
        guard let directory = coordinator.activePreparedDirectory, directory != previous else {
            throw PlaybackCheckFailure.cacheMismatch
        }
        directories.insert(directory)
        try recordStartup(
            "warmReplay", requestedAt: requestedAt, expectedCacheHit: true, sameBaseAs: original, result: &result)
        result.completedSteps.append("warmReplay")
        try await observe("warmReplay", after: marker, result: &result)

        coordinator.selectedSubtitleID = alternate.id
        try await applyChange(
            "subtitleChanged", route: .hls, result: &result, directories: &directories,
            expectedCacheHit: true, sameBaseAs: original)
        coordinator.selectedAudioID = coordinator.audioTracks[1].id
        try await applyChange(
            "audioChanged", route: .hls, result: &result, directories: &directories,
            expectedCacheHit: false, differentBaseFrom: original)
        guard let alternateAudio = result.startups.last?.baseFingerprint else {
            throw PlaybackCheckFailure.cacheMismatch
        }
        coordinator.subtitleDelay = 1
        try await applyChange(
            "subtitleDelayChanged", route: .hls, result: &result, directories: &directories,
            expectedCacheHit: true, sameBaseAs: alternateAudio)
        coordinator.selectedAudioID = coordinator.audioTracks[0].id
        try await applyChange(
            "originalAudioRestored", route: .hls, result: &result, directories: &directories,
            expectedCacheHit: true, sameBaseAs: original)
        coordinator.selectedSubtitleID = nil
        try await applyChange(
            "subtitlesOff", route: .hls, result: &result, directories: &directories,
            expectedCacheHit: true, sameBaseAs: original)
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
            self.coordinator.selectedURL?.path == self.playlistPaths.last
                && self.events[marker...].contains { $0.kind == "ended" && $0.origin == .receiver }
        }
        result.completedSteps.append(step)
        step = "automatic_next_item"
        let nextMarker = events.firstIndex(where: { $0.kind == "ended" })!.advanced(by: 1)
        try await started(after: nextMarker, route: next.route, expectedPosition: 0, result: &result)
        if clip.audioOutput == .compatible {
            guard coordinator.audioOutputMode == .compatible, !coordinator.showConversionAlert else {
                throw PlaybackCheckFailure.conversionRequested
            }
            result.completedSteps.append("next_episode_reuses_equivalent_audio_approval")
        }
        if let directory = coordinator.activePreparedDirectory { directories.insert(directory) }
        guard coordinator.selectedSubtitleID == nil else { throw PlaybackCheckFailure.receiverMismatch }
        try await observe("nextItem", after: nextMarker, result: &result)
        guard PlaybackCheckEvidence.singlePlaylistTransition(loads: loads, events: events[...]),
            coordinator.queueItems.map(\.path) == playlistPaths,
            coordinator.queueItems.first?.watched == true,
            coordinator.queueItems.first?.lastPosition == coordinator.queueItems.first?.duration,
            coordinator.queueItems.last?.watched != true
        else { throw PlaybackCheckFailure.receiverMismatch }
        result.completedSteps.append("season_episode_watched_and_progress_saved")
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
