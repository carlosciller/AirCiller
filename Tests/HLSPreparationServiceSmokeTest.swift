import Darwin
import Foundation

@main
struct HLSPreparationServiceSmokeTest {
    @MainActor
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-HLS-Preparation-Test-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }

        try await verifyCancellation(root: root)
        try await verifySiblingFailure(root: root, failure: "subtitle")
        try await verifySiblingFailure(root: root, failure: "video")
        try await verifyLaunchFailure(root: root)
        print("HLS preparation ownership: cancellation, sibling failures, process join and no late progress: OK")
    }

    @MainActor
    private static func verifyCancellation(root: URL) async throws {
        let directory = try makeDirectory(root, "cancel")
        let fixture = try makeFixture(directory, failure: "none")
        let record = Events()
        let task = Task {
            try await prepare(fixture: fixture, directory: directory, subtitle: false, record: record)
        }
        defer { task.cancel() }
        try await waitForFile(directory.appendingPathComponent("video.pid"))
        task.cancel()
        do {
            _ = try await task.value
            throw Failure.acceptedCancelledPreparation
        } catch is CancellationError {}
        try await verifyJoined(record, directory: directory, expectedProcesses: 1)
    }

    @MainActor
    private static func verifySiblingFailure(root: URL, failure: String) async throws {
        let directory = try makeDirectory(root, "failed-\(failure)")
        let fixture = try makeFixture(directory, failure: failure)
        let record = Events()
        let task = Task {
            try await prepare(fixture: fixture, directory: directory, subtitle: true, record: record)
        }
        let watchdog = Task {
            try await Task.sleep(for: .seconds(8))
            task.cancel()
        }
        defer {
            task.cancel()
            watchdog.cancel()
        }
        do {
            _ = try await task.value
            throw Failure.acceptedFailedPreparation
        } catch AirCillerError.subtitlePreparationFailed {
            guard failure == "subtitle" else { throw Failure.unexpectedFailure }
        } catch AirCillerError.ffmpegStopped {
            guard failure == "video" else { throw Failure.unexpectedFailure }
        }
        try await verifyJoined(record, directory: directory, expectedProcesses: 2)
    }

    @MainActor
    private static func verifyLaunchFailure(root: URL) async throws {
        let directory = try makeDirectory(root, "launch")
        let source = directory.appendingPathComponent("source.mkv")
        try Data([1]).write(to: source)
        let record = Events()
        do {
            _ = try await prepare(
                fixture: Fixture(source: source, helper: directory.appendingPathComponent("missing-helper")),
                directory: directory, subtitle: false, record: record)
            throw Failure.acceptedFailedPreparation
        } catch is CocoaError {}
        try await verifyJoined(record, directory: directory, expectedProcesses: 0)
    }

    @MainActor
    private static func prepare(
        fixture: Fixture, directory: URL, subtitle: Bool, record: Events
    ) async throws -> HLSPreparationResult {
        let track = SubtitleTrack(
            streamIndex: 0, codec: "subrip", language: "eng", title: nil,
            isDefault: true, isForced: false, isHearingImpaired: false,
            externalPath: directory.appendingPathComponent("captions.srt").path)
        let probe = MediaProbe(
            duration: 12, fileSize: 1, bitRate: 1_000_000, videoStreamIndex: 0,
            videoCodec: "h264", videoProfile: nil, videoLevel: nil, hevcCodecIdentifier: nil,
            width: 320, height: 180, frameRate: "24/1", colorTransfer: nil,
            isDolbyVision: false, dolbyVisionProfile: nil, dolbyVisionLevel: nil, dolbyVisionCompatibilityID: nil,
            audioTracks: [], subtitleTracks: [], chapters: [])
        return try await HLSPreparationService.prepare(
            input: fixture.source, probe: probe, audio: nil, outputMode: .original,
            audioDelay: 0, subtitle: subtitle ? track : nil, subtitleDelay: 0,
            outputDirectory: directory, ffmpegURL: fixture.helper,
            observer: { event in record.receive(event) })
    }

    @MainActor
    private static func verifyJoined(_ record: Events, directory: URL, expectedProcesses: Int) async throws {
        guard record.activeProcess == nil, record.observedProcesses.allSatisfy({ !$0.isRunning }) else {
            throw Failure.retainedVideoProcess
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        let processes = files.filter { $0.pathExtension == "pid" }
        guard processes.count == expectedProcesses else { throw Failure.branchDidNotStart }
        for marker in processes {
            guard let pid = Int32(try String(contentsOf: marker, encoding: .utf8)),
                Darwin.kill(pid, 0) == -1, errno == ESRCH
            else { throw Failure.retainedChildProcess }
        }
        guard !files.contains(where: { $0.lastPathComponent.hasPrefix("subtitles-raw-") }),
            !files.contains(where: { ["master.m3u8", "subtitles.m3u8"].contains($0.lastPathComponent) })
        else { throw Failure.retainedSubtitleOutput }
        let count = record.eventCount
        try await Task.sleep(for: .milliseconds(300))
        guard count == record.eventCount else { throw Failure.lateObserverEvent }
    }

    private static func makeFixture(_ directory: URL, failure: String) throws -> Fixture {
        let helper = directory.appendingPathComponent("controlled-ffmpeg")
        let source = directory.appendingPathComponent("source.mkv")
        try Data([1]).write(to: source)
        // Both branches execute the same injected helper. Each announces its PID
        // before the requested failure, so the test cannot pass without starting
        // the sibling. exec keeps the slow helper in the same process we own.
        try """
        #!/bin/sh
        for argument in "$@"; do output="$argument"; done
        directory="${output%/*}"
        case "${output##*/}" in
          subtitles-raw-*) kind=subtitle; sibling=video ;;
          *) kind=video; sibling=subtitle ;;
        esac
        printf '%s' "$$" > "$directory/$kind.pid"
        if [ "$kind" = subtitle ]; then printf 'partial subtitle' > "$output"; fi
        if [ "$kind" = '\(failure)' ]; then
          attempts=0
          while [ ! -f "$directory/$sibling.pid" ]; do
            attempts=$((attempts + 1))
            if [ "$attempts" -ge 500 ]; then exit 99; fi
            /bin/sleep 0.01
          done
          exit 51
        fi
        exec /bin/sleep 30
        """.write(to: helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
        return Fixture(source: source, helper: helper)
    }

    private static func makeDirectory(_ root: URL, _ name: String) throws -> URL {
        let directory = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private static func waitForFile(_ url: URL) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !FileManager.default.fileExists(atPath: url.path) {
            guard ContinuousClock.now < deadline else { throw Failure.branchDidNotStart }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private struct Fixture: Sendable {
        let source: URL
        let helper: URL
    }

    @MainActor
    private final class Events {
        var activeProcess: Process?
        var observedProcesses: [Process] = []
        var eventCount = 0

        func receive(_ event: HLSPreparationEvent) {
            eventCount += 1
            if case .process(let build) = event {
                activeProcess = build?.process
                if let process = build?.process { observedProcesses.append(process) }
            }
        }
    }

    private enum Failure: Error {
        case acceptedCancelledPreparation, acceptedFailedPreparation, unexpectedFailure
        case retainedVideoProcess, retainedChildProcess, branchDidNotStart, retainedSubtitleOutput, lateObserverEvent
    }
}
