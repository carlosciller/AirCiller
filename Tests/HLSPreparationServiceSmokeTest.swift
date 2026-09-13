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
        try await verifyCacheSpacePressure(root: root)
        print(
            "HLS preparation ownership: cancellation, sibling failures, process join, cache space pressure and no late progress: OK"
        )
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
        fixture: Fixture, directory: URL, subtitle: Bool, record: Events,
        cache: PreparedMediaCache? = nil,
        capacityReader: @escaping PreparedMediaCache.CapacityReader = PreparedMediaCache.availableCapacity
    ) async throws -> HLSPreparationResult {
        let track = SubtitleTrack(
            streamIndex: 0, codec: "subrip", language: "eng", title: nil,
            isDefault: true, isForced: false, isHearingImpaired: false,
            externalPath: directory.appendingPathComponent("captions.srt").path)
        return try await HLSPreparationService.prepare(
            input: fixture.source, probe: fixtureProbe(), audio: nil, outputMode: .original,
            audioDelay: 0, subtitle: subtitle ? track : nil, subtitleDelay: 0,
            outputDirectory: directory, ffmpegURL: fixture.helper, cache: cache, capacityReader: capacityReader,
            observer: { event in record.receive(event) })
    }

    private static func fixtureProbe() -> MediaProbe {
        MediaProbe(
            duration: 12, fileSize: 1, bitRate: 1_000_000, videoStreamIndex: 0,
            videoCodec: "h264", videoProfile: nil, videoLevel: nil, hevcCodecIdentifier: nil,
            width: 320, height: 180, frameRate: "24/1", colorTransfer: nil,
            isDolbyVision: false, dolbyVisionProfile: nil, dolbyVisionLevel: nil, dolbyVisionCompatibilityID: nil,
            audioTracks: [], subtitleTracks: [], chapters: [])
    }

    @MainActor
    private static func verifyCacheSpacePressure(root: URL) async throws {
        let directory = try makeDirectory(root, "space-pressure")
        let fixture = try makeFixture(directory, failure: "none")
        // A cache miss should reach this controlled failure only after its disk
        // preflight succeeds. No actual media command runs in these checks.
        try "#!/bin/sh\nexit 51\n".write(to: fixture.helper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: fixture.helper.path)
        let cacheRoot = directory.appendingPathComponent("cache")
        let cache = PreparedMediaCache(rootDirectory: cacheRoot, limitBytes: 1_000_000)
        let base = try makeDirectory(directory, "base")
        try Data("initialization".utf8).write(to: base.appendingPathComponent("video-init.mp4"))
        try Data("segment".utf8).write(to: base.appendingPathComponent("video-00000000.m4s"))
        try """
        #EXTM3U
        #EXT-X-VERSION:7
        #EXT-X-TARGETDURATION:12
        #EXT-X-MEDIA-SEQUENCE:0
        #EXT-X-PLAYLIST-TYPE:VOD
        #EXT-X-MAP:URI="video-init.mp4"
        #EXTINF:12.000000,
        video-00000000.m4s
        #EXT-X-ENDLIST

        """.write(to: base.appendingPathComponent("video.m3u8"), atomically: true, encoding: .utf8)
        let key = try PreparedMediaCache.makeKey(
            source: fixture.source, probe: fixtureProbe(), audio: nil, outputMode: .original,
            audioDelay: 0, multiplexed: false, engineVersion: "hls-base-v1", engineURL: fixture.helper)
        guard try await cache.store(key: key, from: base) else { throw Failure.failedCacheFixture }
        try FileManager.default.removeItem(at: base)
        let retained = cacheRoot.appendingPathComponent(key.digest)
        let warm = try makeDirectory(directory, "warm")
        let warmCapacity = CapacityReadCounter(values: [0])
        let warmResult = try await prepare(
            fixture: fixture, directory: warm, subtitle: false, record: Events(), cache: cache,
            capacityReader: { _ in warmCapacity.next() })
        guard warmResult.usedCache, warmCapacity.count == 0,
            FileManager.default.fileExists(atPath: retained.path)
        else { throw Failure.cacheHitReclaimedSpace }
        // Finish that disposable session so the retained payload is reclaimable.
        // Active-session link accounting is exercised by the cache smoke test.
        try FileManager.default.removeItem(at: warm)

        let newSource = directory.appendingPathComponent("new-source.mkv")
        try Data([2]).write(to: newSource)
        let coldFixture = Fixture(source: newSource, helper: fixture.helper)
        let cold = try makeDirectory(directory, "cold")
        let capacity: PreparedMediaCache.CapacityReader = { _ in
            FileManager.default.fileExists(atPath: retained.path) ? 0 : 1_000_000_000
        }
        do {
            _ = try await prepare(
                fixture: coldFixture, directory: cold, subtitle: false, record: Events(), cache: cache,
                capacityReader: capacity)
            throw Failure.acceptedFailedPreparation
        } catch AirCillerError.ffmpegStopped {}
        guard !FileManager.default.fileExists(atPath: retained.path),
            try Data(contentsOf: fixture.source) == Data([1]),
            try Data(contentsOf: newSource) == Data([2])
        else { throw Failure.pressureCleanupDamagedMedia }

        let unavailableRoot = directory.appendingPathComponent("unavailable-cache")
        try Data([9]).write(to: unavailableRoot)
        let unavailableCache = PreparedMediaCache(rootDirectory: unavailableRoot, limitBytes: 1_000_000)
        let recoveredCapacity = CapacityReadCounter(values: [0, 0, 1_000_000_000])
        let recovered = try makeDirectory(directory, "capacity-recovered")
        do {
            _ = try await prepare(
                fixture: coldFixture, directory: recovered, subtitle: false, record: Events(),
                cache: unavailableCache, capacityReader: { _ in recoveredCapacity.next() })
            throw Failure.acceptedFailedPreparation
        } catch AirCillerError.ffmpegStopped {}
        let insufficient = try makeDirectory(directory, "capacity-insufficient")
        do {
            _ = try await prepare(
                fixture: coldFixture, directory: insufficient, subtitle: false, record: Events(),
                cache: unavailableCache, capacityReader: { _ in 0 })
            throw Failure.acceptedFailedPreparation
        } catch AirCillerError.invalidVODPackage {}
    }

    private final class CapacityReadCounter: @unchecked Sendable {
        private let lock = NSLock()
        private let values: [Int64]
        private var reads = 0

        init(values: [Int64]) { self.values = values }

        func next() -> Int64 {
            lock.lock()
            defer { lock.unlock() }
            let value = values[min(reads, values.count - 1)]
            reads += 1
            return value
        }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return reads
        }
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
        case failedCacheFixture, cacheHitReclaimedSpace, pressureCleanupDamagedMedia
    }
}
