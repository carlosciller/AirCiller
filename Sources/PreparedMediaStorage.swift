import Foundation

extension AirCillerStorage {
    /// A lazily created actor with no scanning, timers or server at startup.
    /// All preparation and visible Settings actions share this one owner.
    static let preparedMediaCache = PreparedMediaCache(
        rootDirectory: preparedMediaCacheDirectory(), limitBytes: preparedMediaCacheLimitBytes)

    static func setPreparedMediaCacheLimitGiB(_ value: Int) async throws {
        let limit = savePreparedMediaCacheLimitGiB(value)
        try await preparedMediaCache.setLimitBytes(Int64(limit) * 1_024 * 1_024 * 1_024)
    }
}
