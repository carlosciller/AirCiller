import Darwin
import Foundation

@main
struct PreparedMediaCacheSmokeTest {
    static func main() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-PreparedCache-Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.mkv")
        let engine = root.appendingPathComponent("engine")
        try Data("source movie".utf8).write(to: source)
        try Data("bundled engine".utf8).write(to: engine)
        let base = try makeBase(root.appendingPathComponent("base"))
        let cacheRoot = root.appendingPathComponent("cache")
        let cache = PreparedMediaCache(rootDirectory: cacheRoot, limitBytes: 1_000_000)
        let key = try makeKey(source, engine: engine)
        try require(key.digest == makeKey(source, engine: engine).digest, "Stable source has stable key")
        try require(try await cache.store(key: key, from: base), "Complete base is retained")
        let entry = cacheRoot.appendingPathComponent(key.digest)
        let names = try FileManager.default.contentsOfDirectory(atPath: entry.path)
        try require(
            !names.contains("master.m3u8") && !names.contains("subtitles.m3u8")
                && !names.contains("raw.srt"), "Session metadata and subtitles are excluded")

        let session = try makeDirectory(root.appendingPathComponent("session"))
        try require(try await cache.checkout(key: key, into: session), "Second preparation reuses base")
        let cachedSegment = entry.appendingPathComponent("video-00000000.m4s")
        let sessionSegment = session.appendingPathComponent("video-00000000.m4s")
        try require(inode(cachedSegment) == inode(sessionSegment), "Media is hard-linked without a payload copy")
        try require(
            inode(entry.appendingPathComponent("video.m3u8")) != inode(session.appendingPathComponent("video.m3u8")),
            "Playlists have independent storage")
        let savedPlaylist = try Data(contentsOf: entry.appendingPathComponent("video.m3u8"))
        try Data("changed session playlist".utf8).write(to: session.appendingPathComponent("video.m3u8"))
        try require(
            try Data(contentsOf: entry.appendingPathComponent("video.m3u8")) == savedPlaylist,
            "Subtitle alignment cannot mutate cached playlists")
        try require(!(try await cache.checkout(key: key, into: session)), "Never overwrite an active session")
        try require(
            try Data(contentsOf: session.appendingPathComponent("video.m3u8")) == Data("changed session playlist".utf8),
            "Rejected checkout preserves destination content")

        let changedKeys = try [
            makeKey(source, engine: engine, audioIndex: 2),
            makeKey(source, engine: engine, mode: .compatible),
            makeKey(source, engine: engine, delay: 0.5),
            makeKey(source, engine: engine, multiplexed: true),
            makeKey(source, engine: engine, version: "next-packager"),
        ]
        try require(
            changedKeys.allSatisfy { $0.digest != key.digest },
            "Track, conversion, timing, layout and engine rules invalidate")
        try require(
            try makeKey(source, engine: engine, delay: 0.0004).digest == key.digest,
            "Sub-millisecond no-op matches command-builder semantics")

        try await checkCorruption(cache: cache, cacheRoot: cacheRoot, key: key, base: base, root: root)
        try await checkPartialCheckout(key: key, root: root)
        try await checkBudgetRefresh(root: root)
        try await checkSpacePressure(root: root, source: source, engine: engine)
        try await checkBoundsAndPruning(
            cache: cache, cacheRoot: cacheRoot, key: key, source: source,
            engine: engine, base: base, sessionSegment: sessionSegment, root: root)

        try Data("different engine".utf8).write(to: engine)
        try require(
            try makeKey(source, engine: engine).digest != key.digest, "Same-version engine replacement invalidates")
        let empty = try makeDirectory(root.appendingPathComponent("empty-after-engine-change"))
        try require(!(try await cache.checkout(key: key, into: empty)), "Old key cannot check out after engine changes")
        try require(!(try await cache.store(key: key, from: base)), "Old key cannot be admitted after engine changes")

        let currentKey = try makeKey(source, engine: engine)
        let oldModified = try source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!
        let oldSize = try Data(contentsOf: source).count
        try Data(repeating: 7, count: oldSize).write(to: source, options: .atomic)
        try FileManager.default.setAttributes([.modificationDate: oldModified], ofItemAtPath: source.path)
        try require(
            try makeKey(source, engine: engine).digest != currentKey.digest,
            "Same-size replacement with restored mtime still invalidates")
        try require(
            !(try await cache.store(key: currentKey, from: base)), "Source changed during preparation is never admitted"
        )

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cache.store(key: currentKey, from: base)
        }
        do {
            _ = try await cancelled.value
            throw failure("Cancellation must propagate")
        } catch is CancellationError {}

        let external = try makeDirectory(root.appendingPathComponent("external"))
        let marker = external.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: marker)
        let linkedRoot = root.appendingPathComponent("linked-cache")
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: external)
        let unsafeCache = PreparedMediaCache(rootDirectory: linkedRoot, limitBytes: 1_000_000)
        do {
            try await unsafeCache.clear()
            throw failure("Symlink cache root must be rejected")
        } catch is TestFailure { throw failure("Symlink cache root was followed") } catch {}
        try require(FileManager.default.fileExists(atPath: marker.path), "Cache clearing cannot traverse symlink roots")
        print(
            "Prepared HLS cache: immutable media, isolated playlists, invalidation, corruption, bounds, eviction and cancellation OK"
        )
    }

    private static func checkCorruption(
        cache: PreparedMediaCache, cacheRoot: URL, key: PreparedMediaCache.Key, base: URL, root: URL
    ) async throws {
        let entry = cacheRoot.appendingPathComponent(key.digest)
        let target = try makeDirectory(root.appendingPathComponent("corruption-checkout"))
        let initFile = entry.appendingPathComponent("video-init.mp4")
        try FileManager.default.removeItem(at: initFile)
        try require(!(try await cache.checkout(key: key, into: target)), "Missing media is a miss")
        try require(try await cache.store(key: key, from: base), "Invalid entry can be rebuilt")
        try FileManager.default.removeItem(at: initFile)
        try FileManager.default.createSymbolicLink(
            at: initFile, withDestinationURL: base.appendingPathComponent("video-init.mp4"))
        try require(!(try await cache.checkout(key: key, into: target)), "Symlinked payload is a miss")
        try require(try await cache.store(key: key, from: base), "Symlinked payload is replaced without following it")

        let manifest = entry.appendingPathComponent("manifest.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as! [String: Any]
        var files = object["files"] as! [[String: Any]]
        files[0]["name"] = "../escaped.m4s"
        object["files"] = files
        try JSONSerialization.data(withJSONObject: object).write(to: manifest)
        try require(!(try await cache.checkout(key: key, into: target)), "Manifest traversal is a miss")
        try require(try await cache.store(key: key, from: base), "Corrupt manifest can be replaced")
        let handle = try FileHandle(forWritingTo: manifest)
        try handle.truncate(atOffset: 17 * 1_024 * 1_024)
        try handle.close()
        try require(
            !(try await cache.checkout(key: key, into: target)), "Oversized sparse manifest is rejected before decoding"
        )
        try require(
            try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty,
            "Corruption checks leave no partially checked-out files")
        try require(try await cache.store(key: key, from: base), "Oversized metadata can be replaced")

        let invalidBase = try makeBase(root.appendingPathComponent("invalid-base"))
        let playlist = invalidBase.appendingPathComponent("video.m3u8")
        let originalText = try String(contentsOf: playlist, encoding: .utf8)
        try originalText.replacingOccurrences(of: "video-00000000.m4s", with: "../outside.m4s")
            .write(to: playlist, atomically: true, encoding: .utf8)
        let otherCache = PreparedMediaCache(
            rootDirectory: root.appendingPathComponent("invalid-cache"), limitBytes: 1_000_000)
        try require(!(try await otherCache.store(key: key, from: invalidBase)), "Playlist traversal cannot be admitted")
        try originalText.replacingOccurrences(of: "#EXT-X-ENDLIST", with: "")
            .write(to: playlist, atomically: true, encoding: .utf8)
        try require(!(try await otherCache.store(key: key, from: invalidBase)), "Unfinished VOD cannot be admitted")
        try originalText.replacingOccurrences(of: "#EXTINF:6.000000,", with: "#EXTINF:")
            .write(to: playlist, atomically: true, encoding: .utf8)
        try require(
            !(try await otherCache.store(key: key, from: invalidBase)),
            "Empty EXTINF is a miss rather than an index trap")
    }

    private static func checkBoundsAndPruning(
        cache: PreparedMediaCache, cacheRoot: URL, key: PreparedMediaCache.Key, source: URL, engine: URL,
        base: URL, sessionSegment: URL, root: URL
    ) async throws {
        let tiny = PreparedMediaCache(rootDirectory: root.appendingPathComponent("tiny-cache"), limitBytes: 1)
        try require(!(try await tiny.store(key: key, from: base)), "Oversized packages bypass retention")
        try require(try await tiny.sizeBytes() == 0, "Skipped packages occupy no cache")
        let secondKey = try makeKey(source, engine: engine, delay: 1)
        try require(try await cache.store(key: secondKey, from: base), "Second package is admitted")
        let firstEntry = cacheRoot.appendingPathComponent(key.digest)
        let secondEntry = cacheRoot.appendingPathComponent(secondKey.digest)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: firstEntry.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2)], ofItemAtPath: secondEntry.path)
        let size = try await cache.sizeBytes()
        try await cache.setLimitBytes(size - 1)
        try require(
            !FileManager.default.fileExists(atPath: firstEntry.path)
                && FileManager.default.fileExists(atPath: secondEntry.path), "Budget eviction is least-recently-used")
        try require(
            try Data(contentsOf: sessionSegment) == Data("video segment".utf8),
            "Eviction preserves a running session's media hard link")
        try await cache.invalidate(key: secondKey)
        try require(
            !FileManager.default.fileExists(atPath: secondEntry.path), "Explicit invalidation removes only its entry")
        try require(
            try Data(contentsOf: sessionSegment) == Data("video segment".utf8),
            "Invalidation never damages existing session links")
        let unrelated = try makeDirectory(cacheRoot.appendingPathComponent("unrelated"))
        try Data("keep".utf8).write(to: unrelated.appendingPathComponent("keep"))
        try await cache.clear()
        try require(try await cache.sizeBytes() == 0, "Clear removes completed entries")
        try require(
            FileManager.default.fileExists(atPath: unrelated.path), "Clear is confined to validated entry names")
        try await cache.setLimitBytes(0)
        try require(!(try await cache.store(key: key, from: base)), "Zero budget disables admission")
        try await cache.setLimitBytes(1_000_000)
    }

    private static func checkPartialCheckout(key: PreparedMediaCache.Key, root: URL) async throws {
        let base = try makeBase(root.appendingPathComponent("race-base"), segmentCount: 800)
        let cache = PreparedMediaCache(rootDirectory: root.appendingPathComponent("race-cache"), limitBytes: 2_000_000)
        try require(try await cache.store(key: key, from: base), "Multi-segment base is admitted")
        let destination = try makeDirectory(root.appendingPathComponent("race-session"))
        let subtitle = destination.appendingPathComponent("raw.vtt")
        try Data("concurrent subtitle".utf8).write(to: subtitle)
        let checkout = Task { try await cache.checkout(key: key, into: destination) }
        let staged = try await waitForStaging(in: destination)
        checkout.cancel()
        do {
            _ = try await checkout.value
            throw failure("Cancellation during staging must propagate")
        } catch is CancellationError {}
        try require(staged, "Cancellation exercised an in-progress checkout")
        try require(
            try FileManager.default.contentsOfDirectory(atPath: destination.path) == ["raw.vtt"],
            "Cancelled checkout removes partial links and preserves concurrent text")

        let collidingCheckout = Task { try await cache.checkout(key: key, into: destination) }
        let collisionStaged = try await waitForStaging(in: destination)
        let collision = destination.appendingPathComponent("video.m3u8")
        try Data("existing owner".utf8).write(to: collision)
        let reused = try await collidingCheckout.value
        try require(collisionStaged && !reused, "A late destination collision is a safe cache miss")
        try require(
            Set(try FileManager.default.contentsOfDirectory(atPath: destination.path)) == ["raw.vtt", "video.m3u8"],
            "Failed promotion rolls back only the cache's own files")
        try require(
            try Data(contentsOf: collision) == Data("existing owner".utf8),
            "Failed promotion never replaces the colliding file")
    }

    private static func waitForStaging(in directory: URL) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if try FileManager.default.contentsOfDirectory(atPath: directory.path).contains(where: {
                $0.hasPrefix(".hls-cache-")
            }) {
                return true
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        return false
    }

    private static func checkBudgetRefresh(root: URL) async throws {
        let directory = try makeDirectory(root.appendingPathComponent("budget-refresh"))
        let emptyEntry = directory.appendingPathComponent(String(repeating: "0", count: 64))
        try makeDirectory(emptyEntry)
        let cache = PreparedMediaCache(rootDirectory: directory, limitBytes: 1_000_000)
        try await cache.setLimitBytes(1_000_000)
        try require(
            !FileManager.default.fileExists(atPath: emptyEntry.path),
            "Initial budget application prunes entries left by an earlier launch")
        try makeDirectory(emptyEntry)
        try await cache.setLimitBytes(1_000_000)
        try require(
            FileManager.default.fileExists(atPath: emptyEntry.path),
            "An unchanged budget does not rescan the catalog on every Play")
        try await cache.setLimitBytes(999_999)
        try require(
            !FileManager.default.fileExists(atPath: emptyEntry.path),
            "A changed budget triggers a fresh prune")

        try FileManager.default.removeItem(at: directory)
        let target = try makeDirectory(root.appendingPathComponent("budget-unavailable-target"))
        try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: target)
        do {
            try await cache.setLimitBytes(999_998)
            throw failure("Unavailable root must fail budget application")
        } catch is TestFailure { throw failure("Budget application followed a symlink") } catch {}
        try FileManager.default.removeItem(at: directory)
        try makeDirectory(directory)
        try makeDirectory(emptyEntry)
        try await cache.setLimitBytes(999_998)
        try require(
            !FileManager.default.fileExists(atPath: emptyEntry.path),
            "A failed budget application is retried even when the requested value is unchanged")
    }

    private static func checkSpacePressure(root: URL, source: URL, engine: URL) async throws {
        let cacheRoot = root.appendingPathComponent("pressure-cache")
        let cache = PreparedMediaCache(rootDirectory: cacheRoot, limitBytes: 1_000_000)
        let keys = try (0..<3).map { try makeKey(source, engine: engine, delay: Double($0)) }
        for (index, key) in keys.enumerated() {
            // Separate preparations have separate inodes, just like real remuxes.
            let base = try makeBase(root.appendingPathComponent("pressure-base-\(index)"))
            try require(try await cache.store(key: key, from: base), "Pressure fixture is admitted")
            try FileManager.default.removeItem(at: base)
        }
        let entries = keys.map { cacheRoot.appendingPathComponent($0.digest) }
        let active = try makeDirectory(root.appendingPathComponent("pressure-active"))
        try require(try await cache.checkout(key: keys[0], into: active), "Active session owns a separate media link")
        for (index, entry) in entries.enumerated() {
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSince1970: Double(index + 1))],
                ofItemAtPath: entry.path)
        }
        let originalBytes = try Data(contentsOf: source)
        let activeSegment = active.appendingPathComponent("video-00000000.m4s")
        // Model capacity which does not increase when the oldest entry loses its
        // cache link: the active session still owns its payload. The next entry
        // is reclaimable. This is deterministic and does not fill the real disk.
        let capacity: PreparedMediaCache.CapacityReader = { _ in
            let firstPinned =
                FileManager.default.fileExists(atPath: activeSegment.path)
                || FileManager.default.fileExists(atPath: entries[0].path)
            let first = firstPinned ? Int64(0) : 100
            let second = FileManager.default.fileExists(atPath: entries[1].path) ? Int64(0) : 100
            let third = FileManager.default.fileExists(atPath: entries[2].path) ? Int64(0) : 100
            return first + second + third
        }
        let free = try await cache.reclaimSpace(requiredFreeBytes: 80, forDirectory: active, capacityReader: capacity)
        try require(free == 100, "Pressure cleanup re-reads capacity instead of assuming manifest bytes were freed")
        try require(
            !FileManager.default.fileExists(atPath: entries[0].path)
                && !FileManager.default.fileExists(atPath: entries[1].path)
                && FileManager.default.fileExists(atPath: entries[2].path),
            "Pressure cleanup respects LRU order and stops after enough actual capacity is reported")
        try require(
            try Data(contentsOf: activeSegment) == Data("video segment".utf8),
            "Pressure eviction preserves active media")
        try require(try Data(contentsOf: source) == originalBytes, "Pressure eviction never modifies the original")
        try require(try await cache.sizeBytes() <= 1_000_000, "Pressure cleanup never increases the retained budget")
        _ = try await cache.reclaimSpace(requiredFreeBytes: 80, forDirectory: active, capacityReader: { _ in 100 })
        try require(
            FileManager.default.fileExists(atPath: entries[2].path), "Enough free space preserves the remaining cache")
        _ = try await cache.reclaimSpace(requiredFreeBytes: 80, forDirectory: active, capacityReader: { _ in nil })
        try require(
            FileManager.default.fileExists(atPath: entries[2].path),
            "Unknown capacity never causes speculative eviction")
    }

    private static func makeBase(_ directory: URL, segmentCount: Int = 1) throws -> URL {
        try makeDirectory(directory)
        for rendition in ["video", "audio"] {
            try Data("\(rendition) init".utf8).write(to: directory.appendingPathComponent("\(rendition)-init.mp4"))
            var segments = ""
            for index in 0..<segmentCount {
                let name = String(format: "%@-%08d.m4s", rendition, index)
                try Data("\(rendition) segment".utf8).write(to: directory.appendingPathComponent(name))
                segments += "#EXTINF:6.000000,\n\(name)\n"
            }
            let playlist = """
                #EXTM3U
                #EXT-X-VERSION:7
                #EXT-X-TARGETDURATION:6
                #EXT-X-MEDIA-SEQUENCE:0
                #EXT-X-PLAYLIST-TYPE:VOD
                #EXT-X-MAP:URI="\(rendition)-init.mp4"
                \(segments.trimmingCharacters(in: .newlines))
                #EXT-X-ENDLIST

                """
            try playlist.write(
                to: directory.appendingPathComponent("\(rendition).m3u8"), atomically: true, encoding: .utf8)
        }
        for name in ["master.m3u8", "subtitles.m3u8", "raw.srt"] {
            try Data("not retained".utf8).write(to: directory.appendingPathComponent(name))
        }
        return directory
    }

    private static func makeKey(
        _ source: URL, engine: URL, audioIndex: Int = 1, mode: AudioOutputMode = .original,
        delay: Double = 0, multiplexed: Bool = false, version: String = "test-engine-v1"
    ) throws -> PreparedMediaCache.Key {
        let audio = AudioTrack(
            streamIndex: audioIndex, codec: "aac", profile: "LC", channels: 2,
            channelLayout: "stereo", language: "en", title: nil, isDefault: true)
        let probe = MediaProbe(
            duration: 6, fileSize: 12, bitRate: nil, videoStreamIndex: 0,
            videoCodec: "h264", videoProfile: "High", videoLevel: 40, hevcCodecIdentifier: nil,
            width: 1920, height: 1080, frameRate: "24/1", colorTransfer: nil,
            isDolbyVision: false, dolbyVisionProfile: nil, dolbyVisionLevel: nil,
            dolbyVisionCompatibilityID: nil, audioTracks: [audio], subtitleTracks: [], chapters: [])
        return try PreparedMediaCache.makeKey(
            source: source, probe: probe, audio: audio,
            outputMode: mode, audioDelay: delay, multiplexed: multiplexed, engineVersion: version, engineURL: engine)
    }

    @discardableResult
    private static func makeDirectory(_ directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        return directory
    }

    private static func inode(_ url: URL) -> UInt64 {
        var attributes = stat()
        _ = url.withUnsafeFileSystemRepresentation { pointer in pointer.map { lstat($0, &attributes) } ?? -1 }
        return attributes.st_ino
    }

    private struct TestFailure: Error { let message: String }
    private static func failure(_ message: String) -> TestFailure { TestFailure(message: message) }
    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw failure(message) }
    }
}
