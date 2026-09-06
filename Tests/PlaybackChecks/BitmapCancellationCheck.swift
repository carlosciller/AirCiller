import Foundation

// Task-scoped observations only. They never substitute a decoder, OCR result or clock.
final class BitmapCancellationTrace: @unchecked Sendable {
    @TaskLocal static var current: BitmapCancellationTrace?
    let cacheDirectory: URL
    private let lock = NSLock()
    private var conversions = 0
    private var recognitions = 0
    private var cues = 0
    private var processes: [Process] = []
    private var directories: [URL] = []

    init(cacheDirectory: URL) { self.cacheDirectory = cacheDirectory }
    func conversionStarted() { lock.withLock { conversions += 1 } }
    func conversionFinished() { lock.withLock { conversions -= 1 } }
    func recognitionStarted() { lock.withLock { recognitions += 1 } }
    func recognitionFinished() { lock.withLock { recognitions -= 1 } }
    func recognizedCue() { lock.withLock { cues += 1 } }
    func recordDirectory(_ url: URL) { lock.withLock { directories.append(url) } }
    func recordProcess(_ process: Process) { lock.withLock { processes.append(process) } }
    var extracting: Bool { lock.withLock { processes.contains { $0.isRunning } } }
    var recognizing: Bool { lock.withLock { cues > 0 && recognitions > 0 } }
    var recognizedCount: Int { lock.withLock { cues } }
    var finished: Bool {
        lock.withLock { conversions == 0 && recognitions == 0 && !processes.contains { $0.isRunning } }
    }
    var outputRemoved: Bool {
        lock.withLock {
            !directories.isEmpty && directories.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }
        }
    }
    var cacheEmpty: Bool {
        !FileManager.default.fileExists(atPath: cacheDirectory.path)
            || (try? FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path).isEmpty) == true
    }
    func terminateOwnedChildren() {
        lock.withLock {
            for process in processes { CancellableProcess(process).terminate() }
        }
    }
}

@MainActor
final class BitmapCancellationCheck {
    private let coordinator: StreamCoordinator
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    init(coordinator: StreamCoordinator) { self.coordinator = coordinator }

    func run(_ plan: PlaybackCheckPlan, report original: PlaybackCheckReport) async -> PlaybackCheckReport {
        var report = original
        coordinator.airPlay.playbackCheckLocalOnly = true
        for (index, clip) in plan.clips.enumerated() {
            for phase in ["extractionStop", "ocrStop", "ocrReplacement"] {
                print("Bitmap check \(index + 1)/\(plan.clips.count): \(phase)")
                fflush(nil)
                let replacement = plan.clips[(index + 1) % plan.clips.count]
                let result = await run(clip, replacement: replacement, number: index + 1, phase: phase)
                report.results.append(result)
                if let failure = result.failure {
                    report.failure = failure
                    report.outcome = failure.outcome
                    return report
                }
            }
        }
        report.outcome = "local_bitmap_cancellation_passed"
        return report
    }

    private func run(
        _ clip: PlaybackCheckPlan.Clip, replacement: PlaybackCheckPlan.Clip, number: Int, phase: String
    ) async -> PlaybackCheckResult {
        var result = PlaybackCheckResult(clip: number, route: clip.route, subtitlesRequested: true)
        result.profile = .cancelBitmap
        let began = now
        result.startedAtUptime = began
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AirCiller-BitmapCheck-\(UUID())")
        let trace = BitmapCancellationTrace(cacheDirectory: root.appendingPathComponent("cache"))
        var prepared: URL?
        var step = "analysis"
        defer {
            coordinator.stop()
            trace.terminateOwnedChildren()
            try? FileManager.default.removeItem(at: root)
        }
        do {
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            coordinator.loadVideo(URL(fileURLWithPath: clip.path), autoStart: false, startingAt: 0)
            try await wait(seconds: 30) { self.coordinator.probeInfo != nil }
            guard let probe = coordinator.probeInfo, (45...180).contains(probe.duration),
                (clip.route == .directHDR) == probe.isHDR,
                let track = coordinator.subtitleTracks.first(where: { $0.streamIndex == clip.subtitleIndex }),
                ["hdmv_pgs_subtitle", "dvd_subtitle"].contains(track.codec.lowercased()),
                coordinator.selectedAudio?.canPassThrough == true
            else { throw PlaybackCheckFailure.unsupportedFixture }
            coordinator.selectedSubtitleID = track.id
            coordinator.audioOutputMode = .original
            try BitmapCancellationTrace.$current.withValue(trace) { try coordinator.playbackCheckPrepareBitmap() }
            step = phase
            try await wait(seconds: 45) { phase == "extractionStop" ? trace.extracting : trace.recognizing }
            guard coordinator.isPreparing, !coordinator.isStreaming else { throw PlaybackCheckFailure.receiverMismatch }
            prepared = coordinator.activePreparedDirectory
            let recognized = trace.recognizedCount
            let cancelledAt = now
            if phase == "ocrReplacement" {
                guard replacement.path != clip.path else { throw PlaybackCheckFailure.invalidPlan }
                coordinator.loadVideo(URL(fileURLWithPath: replacement.path), autoStart: false, startingAt: 0)
            } else {
                coordinator.stop()
            }
            try await wait(seconds: 8) { self.coordinator.playbackCheckRuntimeIsIdle && trace.finished }
            let latency = now - cancelledAt
            try await Task.sleep(for: .seconds(2))
            guard coordinator.playbackCheckRuntimeIsIdle, trace.finished, trace.outputRemoved, trace.cacheEmpty,
                prepared.map({ !FileManager.default.fileExists(atPath: $0.path) }) == true,
                coordinator.airPlay.playbackCheckBlockedStarts == 0,
                !coordinator.streamTelemetry.hasConfirmedMediaRequest,
                !coordinator.hasError,
                coordinator.selectedURL?.path == (phase == "ocrReplacement" ? replacement.path : clip.path)
            else { throw PlaybackCheckFailure.cleanupFailed }
            result.completedSteps = [
                "real_bitmap_work_observed", phase, "no_delayed_playback_or_cache", "stop_and_cleanup",
            ]
            result.bitmapCancellation = BitmapCancellationEvidence(
                phase: phase, codec: track.codec, cancellationSeconds: latency, recognizedCuesBeforeStop: recognized)
            result.cleanupConfirmed = true
        } catch {
            result.failure = (error as? PlaybackCheckFailure) ?? .applicationError
            result.failedStep = step
            coordinator.stop()
            trace.terminateOwnedChildren()
            let deadline = now + 8
            while !trace.finished, now < deadline { try? await Task.sleep(for: .milliseconds(50)) }
            result.cleanupConfirmed = trace.finished && coordinator.playbackCheckRuntimeIsIdle
        }
        result.elapsedSeconds = now - began
        return result
    }

    private func wait(seconds: Double, until condition: () -> Bool) async throws {
        let deadline = now + seconds
        while true {
            try Task.checkCancellation()
            guard !coordinator.hasError, !coordinator.showConversionAlert,
                !coordinator.airPlay.isPairingPresented, coordinator.airPlay.playbackCheckBlockedStarts == 0
            else { throw PlaybackCheckFailure.applicationError }
            if condition() { return }
            guard now < deadline else { throw PlaybackCheckFailure.timedOut }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
