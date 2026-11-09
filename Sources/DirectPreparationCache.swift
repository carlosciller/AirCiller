import Foundation

/// Coordinates optional immutable MP4 reuse. Validation always runs, including
/// on a hit. A rejected hit is removed and rebuilt once; cancellation never
/// starts a replacement build. The normal session owns the output directory
/// and admits a new result only after its additional player checks pass.
@MainActor
enum DirectPreparationCache {
    struct Result {
        let probe: MediaProbe
        let usedCache: Bool
    }

    static func prepare(
        directory: URL, cache: PreparedMediaCache?, key: PreparedMediaCache.Key?,
        build: () async throws -> Void,
        validate: () async throws -> MediaProbe
    ) async throws -> Result {
        try Task.checkCancellation()
        if let cache, let key, try await cache.checkout(key: key, into: directory) {
            do {
                let probe = try await validate()
                try Task.checkCancellation()
                return Result(probe: probe, usedCache: true)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                try? await cache.invalidate(key: key)
                try Task.checkCancellation()
                try FileManager.default.removeItem(at: directory.appendingPathComponent("movie.mp4"))
            }
        }
        try Task.checkCancellation()
        try await build()
        try Task.checkCancellation()
        let probe = try await validate()
        try Task.checkCancellation()
        return Result(probe: probe, usedCache: false)
    }
}
