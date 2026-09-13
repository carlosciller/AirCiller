import CryptoKit
import Foundation

// Private, opt-in test evidence. These are generated base-file names, never source paths.
struct PlaybackCheckBaseFingerprint: Codable, Equatable, Sendable {
    struct File: Codable, Equatable, Sendable {
        let name: String
        let bytes: Int64
        let sha256: String
    }
    let files: [File]

    static func read(directory: URL) throws -> Self {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Array(keys))
        var files: [File] = []
        var total: Int64 = 0
        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = url.lastPathComponent
            guard name.range(of: #"^(video|audio)-(init\.mp4|[0-9]+\.m4s)$"#, options: .regularExpression) != nil
            else { continue }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                let size = values.fileSize, size > 0
            else { throw PlaybackCheckFailure.cacheMismatch }
            total += Int64(size)
            // Intended for short synthetic fixtures, never a full movie scan.
            guard total <= 256 * 1_024 * 1_024 else { throw PlaybackCheckFailure.evidenceLimit }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var hash = SHA256()
            var bytes: Int64 = 0
            while let chunk = try handle.read(upToCount: 1_024 * 1_024), !chunk.isEmpty {
                try Task.checkCancellation()
                bytes += Int64(chunk.count)
                guard bytes <= Int64(size) else { throw PlaybackCheckFailure.cacheMismatch }
                hash.update(data: chunk)
            }
            guard bytes == Int64(size) else { throw PlaybackCheckFailure.cacheMismatch }
            files.append(
                File(name: name, bytes: bytes, sha256: hash.finalize().map { String(format: "%02x", $0) }.joined()))
        }
        guard files.contains(where: { $0.name == "video-init.mp4" }),
            files.contains(where: { $0.name.hasPrefix("video-") && $0.name.hasSuffix(".m4s") })
        else { throw PlaybackCheckFailure.cacheMismatch }
        return Self(files: files)
    }
}

struct PlaybackCheckStartupEvidence: Encodable {
    let label: String
    // Start/action request and receiver confirmation use the capture host's monotonic clock.
    // Neither this confirmation nor a media HTTP request is a visible-frame claim.
    let requestedAtUptime: Double
    let receiverConfirmedAtUptime: Double
    let cacheHit: Bool
    let snapshot: PlaybackStartupTrace.Snapshot
    let expectedCacheHit: Bool?
    let baseFingerprint: PlaybackCheckBaseFingerprint?

    func validate(
        sameBaseAs: PlaybackCheckBaseFingerprint? = nil, differentBaseFrom: PlaybackCheckBaseFingerprint? = nil
    )
        throws
    {
        guard requestedAtUptime.isFinite, receiverConfirmedAtUptime.isFinite,
            requestedAtUptime <= snapshot.startedAtUptimeSeconds,
            snapshot.startedAtUptimeSeconds + snapshot.elapsedSeconds <= receiverConfirmedAtUptime + 0.01,
            snapshot.outcome == .receiverMediaRequest,
            snapshot.spans.contains(where: { $0.stage == .receiverRequest && $0.state == .completed })
        else { throw PlaybackCheckFailure.cacheMismatch }
        if let expectedCacheHit {
            guard cacheHit == expectedCacheHit, baseFingerprint != nil,
                snapshot.spans.contains(where: { $0.stage == .cacheLookup && $0.state == .completed }),
                snapshot.spans.contains(where: { $0.stage == .packaging && $0.state == .completed }) == !cacheHit
            else { throw PlaybackCheckFailure.cacheMismatch }
        }
        if let sameBaseAs {
            guard baseFingerprint == sameBaseAs else { throw PlaybackCheckFailure.cacheMismatch }
        }
        if let differentBaseFrom {
            guard let baseFingerprint, baseFingerprint != differentBaseFrom else {
                throw PlaybackCheckFailure.cacheMismatch
            }
        }
    }
}

#if AIRCILLER_PLAYBACK_CHECKS
    @MainActor
    enum PlaybackCheckStartupRecorder {
        static func record(
            coordinator: StreamCoordinator, label: String, requestedAtUptime: Double,
            expectedCacheHit: Bool? = nil
        ) throws -> PlaybackCheckStartupEvidence {
            guard let snapshot = coordinator.playbackCheckStartupSnapshot else {
                throw PlaybackCheckFailure.cacheMismatch
            }
            let confirmation = ProcessInfo.processInfo.systemUptime
            let fingerprint: PlaybackCheckBaseFingerprint?
            if expectedCacheHit != nil {
                guard let directory = coordinator.activePreparedDirectory else {
                    throw PlaybackCheckFailure.cacheMismatch
                }
                fingerprint = try PlaybackCheckBaseFingerprint.read(directory: directory)
            } else {
                fingerprint = nil
            }
            return PlaybackCheckStartupEvidence(
                label: label, requestedAtUptime: requestedAtUptime, receiverConfirmedAtUptime: confirmation,
                cacheHit: coordinator.playbackCheckUsedPreparedMediaCache, snapshot: snapshot,
                expectedCacheHit: expectedCacheHit, baseFingerprint: fingerprint)
        }
    }
#endif
