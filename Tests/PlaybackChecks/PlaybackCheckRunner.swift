import AppKit
import Foundation
import SwiftUI

@MainActor
final class PlaybackCheckRunner {
    private let coordinator: StreamCoordinator
    private var events: [PlaybackCheckEvent] = []
    private var overflowed = false
    private var began = ProcessInfo.processInfo.systemUptime
    private var step = "preflight" {
        didSet {
            print("Checking: \(step)")
            fflush(nil)
        }
    }

    init(coordinator: StreamCoordinator) {
        self.coordinator = coordinator
        coordinator.airPlay.onPlaybackCheckEvent = { [weak self] kind, source, position, duration, playing, requestID in
            guard let self,
                let event = PlaybackCheckEvent(
                    seconds: self.now - self.began, kind: kind, source: source,
                    position: position, duration: duration, playing: playing, requestID: requestID
                )
            else { return }
            guard self.events.count < 4_096 else {
                self.overflowed = true
                return
            }
            self.events.append(event)
        }
    }

    private var now: Double { ProcessInfo.processInfo.systemUptime }

    func run(_ plan: PlaybackCheckPlan) async -> PlaybackCheckReport {
        var report = PlaybackCheckReport(
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            outcome: "failed"
        )
        if plan.selectedProfile == .cancelBitmap {
            return await BitmapCancellationCheck(coordinator: coordinator).run(plan, report: report)
        }
        step = "discovery_and_authorization"
        if let marker = plan.captureReadyFile, FileManager.default.fileExists(atPath: marker) {
            report.failure = .invalidPlan
            report.outcome = "blocked"
            return report
        }
        await coordinator.airPlay.refreshDevices()
        guard coordinator.airPlay.devices.contains(where: { $0.id == plan.deviceID }) else {
            report.failure = .deviceUnavailable
            report.outcome = PlaybackCheckFailure.deviceUnavailable.outcome
            return report
        }
        await coordinator.airPlay.selectDevice(plan.deviceID)
        do {
            try await coordinator.airPlay.refreshAuthorization()
            guard coordinator.airPlay.authorizationState == .authorized else {
                throw PlaybackCheckFailure.authorizationUnavailable
            }
            try await coordinator.airPlay.validateAuthorization()
        } catch {
            report.failure = .authorizationUnavailable
            report.outcome = PlaybackCheckFailure.authorizationUnavailable.outcome
            return report
        }

        if let marker = plan.captureReadyFile {
            step = "awaiting_capture_ready"
            do {
                // Start the bounded capture only after Keychain/receiver authorization.
                // The marker coordinates startup; it is never audiovisual pass evidence.
                try await wait(seconds: 120) { FileManager.default.fileExists(atPath: marker) }
            } catch {
                report.failure = (error as? PlaybackCheckFailure) ?? .interrupted
                report.outcome = report.failure?.outcome ?? "incomplete"
                return report
            }
        }

        for (index, clip) in plan.clips.enumerated() {
            let result: PlaybackCheckResult
            if plan.selectedProfile == .controls {
                result = await runClip(clip, number: index + 1)
            } else {
                result = await PlaybackCheckScenarioRunner(coordinator: coordinator).run(
                    clip, profile: plan.selectedProfile)
            }
            report.results.append(result)
            if result.failure != nil {
                report.failure = result.failure
                report.outcome = result.failure?.outcome ?? "failed"
                return report
            }
        }
        report.outcome =
            report.results.contains(where: { !$0.unverifiedChecks.isEmpty })
            ? "inconclusive" : "automated_checks_passed_output_unverified"
        return report
    }

    private func runClip(_ clip: PlaybackCheckPlan.Clip, number: Int) async -> PlaybackCheckResult {
        began = now
        events.removeAll(keepingCapacity: true)
        overflowed = false
        var result = PlaybackCheckResult(
            clip: number, route: clip.route,
            subtitlesRequested: clip.subtitleIndex != nil || clip.externalSubtitle != nil
        )
        result.startedAtUptime = began
        var preparedDirectory: URL?
        do {
            step = "analysis"
            print("Clip \(number): analysis (\(clip.route.rawValue))")
            fflush(nil)
            coordinator.loadVideo(URL(fileURLWithPath: clip.path), autoStart: false, startingAt: 0)
            try await wait(seconds: 40) { self.coordinator.probeInfo != nil && self.coordinator.network.isReady }
            guard let probe = coordinator.probeInfo, (45...180).contains(probe.duration),
                ["h264", "hevc"].contains(probe.videoCodec.lowercased()),
                coordinator.selectedAudio?.canPassThrough == true,
                clip.route == .hls ? !probe.isHDR : probe.isHDR
            else { throw PlaybackCheckFailure.unsupportedFixture }

            coordinator.selectedSubtitleID = nil
            if let index = clip.subtitleIndex {
                guard let subtitle = coordinator.subtitleTracks.first(where: { $0.streamIndex == index }),
                    subtitle.unsupportedReason == nil
                else { throw PlaybackCheckFailure.unsupportedFixture }
                coordinator.selectedSubtitleID = subtitle.id
            } else if let path = clip.externalSubtitle {
                guard let subtitle = coordinator.registerExternalSubtitle(URL(fileURLWithPath: path)) else {
                    throw PlaybackCheckFailure.unsupportedFixture
                }
                coordinator.selectedSubtitleID = subtitle.id
            }
            coordinator.audioOutputMode = .original
            result.completedSteps.append(step)

            step = "start_and_media_request"
            coordinator.start(at: 0)
            try await wait(seconds: 100) {
                self.coordinator.isStreaming && self.coordinator.isPlaying
                    && self.coordinator.streamTelemetry.hasConfirmedMediaRequest
                    && self.events.contains {
                        $0.kind == "playing" && $0.duration.map { abs($0 - probe.duration) <= 2.5 } == true
                    }
            }
            preparedDirectory = coordinator.activePreparedDirectory
            guard let directory = preparedDirectory else { throw PlaybackCheckFailure.applicationError }
            let expectedFile: String
            switch clip.route {
            case .directHDR: expectedFile = "movie.mp4"
            case .hls: expectedFile = "master.m3u8"
            case .hlsHDR: expectedFile = "video.m3u8"
            }
            guard FileManager.default.fileExists(atPath: directory.appendingPathComponent(expectedFile).path) else {
                throw PlaybackCheckFailure.unsupportedFixture
            }
            result.completedSteps.append(step)

            // Some receivers report state without positions, even after commands.
            // Preserve that distinction instead of treating the UI clock as evidence.
            step = "pause"
            try await Task.sleep(for: .seconds(3))
            var marker = events.count
            try requestPlayback(playing: false)
            try await wait(seconds: 15) {
                PlaybackCheckEvidence.paused(self.events[marker...]) && !self.coordinator.isPlaying
            }
            result.completedSteps.append(step)

            step = "resume"
            marker = events.count
            try requestPlayback(playing: true)
            try await wait(seconds: 15) {
                self.events[marker...].contains { $0.receiverIsPlaying == true }
                    && self.coordinator.isPlaying
            }
            // A receiver may omit the paused position and supply it on resume.
            // Evaluate this interval before issuing any seek commands.
            try record(PlaybackCheckEvidence.progressVerdict(events[...]), as: "receiver_progress", in: &result)
            try await Task.sleep(for: .seconds(3))
            try requestPlayback(playing: false)
            try await wait(seconds: 15) {
                PlaybackCheckEvidence.paused(self.events[marker...]) && !self.coordinator.isPlaying
            }
            result.completedSteps.append(step)

            step = "seek_commands_acknowledged"
            marker = events.count
            coordinator.seek(to: 15)
            try await wait(seconds: 15) {
                PlaybackCheckEvidence.seekCommandsAcknowledged(self.events[marker...], target: 15, count: 1)
            }
            marker = events.count
            for offset in [10.0, 10.0, -10.0, -10.0] {
                coordinator.skip(by: offset)
                try await Task.sleep(for: .milliseconds(120))
            }
            try await wait(seconds: 15) {
                PlaybackCheckEvidence.seekCommandsAcknowledged(self.events[marker...], target: 15, count: 4)
            }
            result.completedSteps.append(step)

            step = "resume_after_seeks"
            let resumeMarker = events.count
            try requestPlayback(playing: true)
            try await wait(seconds: 20) {
                self.events[resumeMarker...].contains { $0.receiverIsPlaying == true } && self.coordinator.isPlaying
            }
            result.completedSteps.append(step)
            try record(
                PlaybackCheckEvidence.seekVerdict(events[marker...], target: 15, count: 4),
                as: "receiver_seek_destination", in: &result
            )
            try await Task.sleep(for: .seconds(3))
        } catch {
            result.failure = (error as? PlaybackCheckFailure) ?? (Task.isCancelled ? .interrupted : .applicationError)
            result.failedStep = step
        }

        // Stop always runs, including analysis failures and missing receiver evidence.
        let cleanupDirectory = preparedDirectory ?? coordinator.activePreparedDirectory
        coordinator.stop()
        let deadline = now + 8
        while !coordinator.playbackCheckRuntimeIsIdle, now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        result.cleanupConfirmed =
            coordinator.playbackCheckRuntimeIsIdle
            && (cleanupDirectory.map { !FileManager.default.fileExists(atPath: $0.path) } ?? true)
        if !result.cleanupConfirmed {
            result.failure = .cleanupFailed
            result.failedStep = "stop_and_cleanup"
        } else {
            result.completedSteps.append("stop_and_cleanup")
        }
        result.events = events
        result.elapsedSeconds = now - began
        let outcome =
            result.failure?.rawValue
            ?? (result.unverifiedChecks.isEmpty ? "automatic checks passed" : "controls checked; position unverified")
        print("Clip \(number): \(outcome); audiovisual check pending")
        fflush(nil)
        return result
    }

    private func requestPlayback(playing: Bool) throws {
        guard
            PlaybackCheckControl.request(
                playing: playing, pause: { coordinator.airPlay.pause() }, resume: { coordinator.airPlay.resume() }
            )
        else { throw PlaybackCheckFailure.applicationError }
    }

    private func record(
        _ verdict: PlaybackCheckEvidence.Verdict, as name: String, in result: inout PlaybackCheckResult
    ) throws {
        switch verdict {
        case .confirmed: result.completedSteps.append(name)
        case .missing: result.unverifiedChecks.append(name)
        case .mismatch: throw PlaybackCheckFailure.receiverMismatch
        }
    }

    private func wait(seconds: Double, until condition: () -> Bool) async throws {
        let deadline = now + seconds
        while true {
            try Task.checkCancellation()
            if coordinator.airPlay.isPairingPresented { throw PlaybackCheckFailure.authorizationUnavailable }
            if coordinator.showConversionAlert { throw PlaybackCheckFailure.conversionRequested }
            if coordinator.hasError { throw PlaybackCheckFailure.applicationError }
            if overflowed { throw PlaybackCheckFailure.evidenceLimit }
            if events.contains(where: { ["error", "ended", "stopped"].contains($0.kind) }) {
                throw PlaybackCheckFailure.unexpectedTerminalEvent
            }
            if condition() { return }
            guard now < deadline else { throw PlaybackCheckFailure.timedOut }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}

@main
@MainActor
enum PlaybackCheckMain {
    private static let identifier = "local.carlosciller.AirCiller.PlaybackChecks"

    static func main() {
        // Validation does not initialize the app, discover a TV or access Keychain.
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.count == 2,
                ["--authorize-keychain", "--check-keychain"].contains(arguments[0])
            {
                guard Bundle.main.bundleIdentifier == identifier else { throw PlaybackCheckFailure.wrongBuild }
                guard !arguments[1].isEmpty, arguments[1].utf8.count <= 256 else {
                    throw PlaybackCheckFailure.invalidPlan
                }
                if arguments[0] == "--check-keychain" { try disableKeychainUI() }
                // One explicit read in this exact signed app. No scan, pairing,
                // writes, playback, preferences reset or credential output.
                do {
                    let backend = KeychainAirPlayCredentialBackend(
                        allowInteraction: arguments[0] == "--authorize-keychain")
                    guard let value = try backend.credential(for: arguments[1]),
                        !value.isEmpty
                    else { throw PlaybackCheckFailure.authorizationUnavailable }
                } catch {
                    throw PlaybackCheckFailure.authorizationUnavailable
                }
                print("Existing AirPlay credential is accessible. No Apple TV playback was started.")
                return
            }
            guard arguments.count == 2 || arguments.count == 5 else { throw PlaybackCheckFailure.invalidPlan }
            guard arguments[0] == "--validate-only" || arguments[0] == "--run" else {
                throw PlaybackCheckFailure.invalidPlan
            }
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: arguments[1]))
            defer { try? handle.close() }
            let plan = try PlaybackCheckPlan.decode(handle.read(upToCount: 65_537) ?? Data())
            for clip in plan.clips {
                try checkFile(clip.path, maximumSize: 2_147_483_648)
                if let path = clip.externalSubtitle { try checkFile(path, maximumSize: 4_194_304) }
                if let path = clip.alternateSubtitle { try checkFile(path, maximumSize: 4_194_304) }
                if let next = clip.nextClip { try checkFile(next.path, maximumSize: 2_147_483_648) }
            }
            if arguments[0] == "--validate-only", arguments.count == 2 {
                print("Playback plan and local file bounds: OK. No media decoding or Apple TV test performed.")
                return
            }
            guard arguments.count == 5, arguments[0] == "--run", arguments[2] == "--report",
                arguments[4] == (plan.selectedProfile == .cancelBitmap ? "--local-only" : "--tv-is-idle")
            else { throw PlaybackCheckFailure.playbackNotAuthorized }
            guard Bundle.main.bundleIdentifier == identifier else { throw PlaybackCheckFailure.wrongBuild }
            try disableKeychainUI()
            let output = URL(fileURLWithPath: arguments[3])
            guard output.pathExtension == "json", !FileManager.default.fileExists(atPath: output.path) else {
                throw PlaybackCheckFailure.invalidPlan
            }
            guard
                !NSWorkspace.shared.runningApplications.contains(where: {
                    $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                        && ($0.bundleIdentifier?.hasPrefix("local.carlosciller.AirCiller") == true
                            || $0.executableURL?.lastPathComponent == "AirCiller")
                })
            else { throw PlaybackCheckFailure.appAlreadyRunning }

            // A crash, forced quit or closed window leaves an explicit incomplete report, never a pass.
            let incomplete = PlaybackCheckReport(appVersion: "unknown", outcome: "incomplete", failure: .interrupted)
            try JSONEncoder().encode(incomplete).write(to: output, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
            UserDefaults.standard.removePersistentDomain(forName: identifier)
            let application = NSApplication.shared
            let delegate = AirCillerAppDelegate()
            application.delegate = delegate
            let coordinator = StreamCoordinator()
            let runner = PlaybackCheckRunner(coordinator: coordinator)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1_080, height: 812),
                styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
            )
            window.title = "AirCiller Playback Checks"
            window.contentView = NSHostingView(rootView: ContentView(coordinator: coordinator, appDelegate: delegate))
            window.center()
            window.makeKeyAndOrderFront(nil)
            Task {
                let report = await runner.run(plan)
                coordinator.stop()
                UserDefaults.standard.removePersistentDomain(forName: identifier)
                do {
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    try encoder.encode(report).write(to: output, options: .atomic)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
                    print("Report: \(report.outcome). No audiovisual output was captured or verified.")
                    if report.failure == .authorizationUnavailable {
                        print(
                            "Keychain access is unavailable. Authorize this signed check app once with --authorize-keychain; the batch never opens password dialogs."
                        )
                    }
                    exit(report.failure == nil ? 0 : 1)
                } catch {
                    print("Could not save the playback check report.")
                    exit(1)
                }
            }
            withExtendedLifetime((delegate, window, runner)) { application.run() }
        } catch {
            // Decoding errors and OS messages can contain media paths; only export fixed categories.
            print("Playback checks refused: \((error as? PlaybackCheckFailure)?.rawValue ?? "invalidInput")")
            exit(2)
        }
    }

    private static func disableKeychainUI() throws {
        guard ACPlaybackChecksDisableKeychainUI() == 0 else {
            throw PlaybackCheckFailure.authorizationUnavailable
        }
    }

    private static func checkFile(_ path: String, maximumSize: Int64) throws {
        let values = try URL(fileURLWithPath: path).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maximumSize else {
            throw PlaybackCheckFailure.missingMedia
        }
    }
}
