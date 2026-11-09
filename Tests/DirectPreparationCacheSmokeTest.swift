import Foundation

@main
@MainActor
struct DirectPreparationCacheSmokeTest {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AirCiller-DirectCache-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mkv")
        let engine = root.appendingPathComponent("engine")
        let subtitle = root.appendingPathComponent("subtitle.vtt")
        let companion = root.appendingPathComponent("subtitle.sub")
        for file in [source, engine, subtitle, companion] { try Data([1]).write(to: file) }
        let cache = PreparedMediaCache(rootDirectory: root.appendingPathComponent("cache"), limitBytes: 50_000)
        func key(_ arguments: [String] = ["-c:v", "copy"], text: String = "caption") throws -> PreparedMediaCache.Key {
            try PreparedMediaCache.makeDirectKey(
                source: source, engineURL: engine, arguments: arguments, subtitleInputs: [subtitle, companion],
                recognizedText: Data(text.utf8))
        }
        let originalKey = try key()
        try require(originalKey.digest == key().digest, "Stable direct key")
        try require(originalKey.digest != key(["-itsoffset", "1"]).digest, "Mux arguments invalidate")
        try require(originalKey.digest != key(text: "corrected caption").digest, "OCR content invalidates")
        let bytes = Data(repeating: 7, count: 8192)
        var builds = 0
        var validations = 0
        func prepare(_ name: String, rejectCache: Bool = false, cancelValidation: Bool = false) async throws
            -> DirectPreparationCache.Result
        {
            let directory = root.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let before = builds
            let result = try await DirectPreparationCache.prepare(
                directory: directory, cache: cache, key: originalKey,
                build: {
                    builds += 1
                    try bytes.write(to: directory.appendingPathComponent("movie.mp4"))
                },
                validate: {
                    validations += 1
                    if cancelValidation {
                        withUnsafeCurrentTask { $0?.cancel() }
                        throw CancellationError()
                    }
                    if rejectCache && builds == before { throw Failure.invalidCachedMedia }
                    try require(try Data(contentsOf: directory.appendingPathComponent("movie.mp4")) == bytes, "Bytes")
                    return probe
                })
            if !result.usedCache { _ = try await cache.store(key: originalKey, from: directory) }
            return result
        }
        let cold = try await prepare("cold")
        let warm = try await prepare("warm")
        try require(
            !cold.usedCache && warm.usedCache && builds == 1 && validations == 2, "Hit skips build, not validation")
        let rebuilt = try await prepare("rejected-hit", rejectCache: true)
        try require(!rebuilt.usedCache && builds == 2 && validations == 4, "Bad hit rebuilds once")
        let reused = try await prepare("after-repair")
        try require(reused.usedCache && builds == 2, "Repaired entry reusable")
        let cancelledHit = Task { try await prepare("cancelled-hit", cancelValidation: true) }
        do {
            _ = try await cancelledHit.value
            throw Failure.notCancelled
        } catch is CancellationError {}
        let afterCancellation = try await prepare("after-cancellation")
        try require(afterCancellation.usedCache && builds == 2, "Cancelled validation neither rebuilds nor evicts")
        // Eviction removes cache ownership only, not an active session's media.
        try await cache.clear()
        try require(
            try Data(contentsOf: root.appendingPathComponent("warm/movie.mp4")) == bytes, "Clear preserves session")
        try await cache.setLimitBytes(0)
        let off = try await prepare("off")
        let retainedBytes = try await cache.sizeBytes()
        try require(!off.usedCache && retainedBytes == 0, "Off retains nothing")
        try await cache.setLimitBytes(50_000)
        _ = try await prepare("before-sidecar-change")
        try Data([2]).write(to: companion, options: .atomic)
        try require(originalKey.digest != key().digest, "VobSub companion invalidates")
        let missDirectory = root.appendingPathComponent("changed-dependency")
        try FileManager.default.createDirectory(at: missDirectory, withIntermediateDirectories: false)
        try require(!(try await cache.checkout(key: originalKey, into: missDirectory)), "Stale dependency refused")
        let beforeCancel = builds
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await prepare("cancelled")
        }
        do {
            _ = try await cancelled.value
            throw Failure.notCancelled
        } catch is CancellationError {}
        try require(builds == beforeCancel, "Cancelled request never builds")
        print(
            "Direct MP4 reuse: exact settings/OCR/dependencies, validation, recovery, Off, clear and cancellation: OK")
    }

    private static var probe: MediaProbe {
        MediaProbe(
            duration: 6, fileSize: 8192, bitRate: nil, videoStreamIndex: 0,
            videoCodec: "hevc", videoProfile: "Main 10", videoLevel: 120, hevcCodecIdentifier: nil,
            width: 1920, height: 1080, frameRate: "24/1", colorTransfer: "smpte2084",
            isDolbyVision: false, dolbyVisionProfile: nil, dolbyVisionLevel: nil,
            dolbyVisionCompatibilityID: nil, audioTracks: [], subtitleTracks: [], chapters: [])
    }

    private enum Failure: Error {
        case invalidCachedMedia
        case assertion(String)
        case notCancelled
    }
    private static func require(_ value: Bool, _ message: String) throws {
        if !value { throw Failure.assertion(message) }
    }
}
