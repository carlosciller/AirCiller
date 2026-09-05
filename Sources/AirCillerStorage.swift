import Foundation

struct AirCillerStorageSnapshot: Equatable, Sendable {
    let subtitleCacheBytes: Int64
    let preparedMediaBytes: Int64
    let subtitleCacheLimitBytes: Int64
}

enum AirCillerStorage {
    static let subtitleCacheLimitOptionsMB = [128, 256, 512, 1_024, 2_048]
    static let defaultSubtitleCacheLimitMB = 512

    private static let subtitleCacheLimitKey = "subtitleOCRCacheLimitMB"

    static var subtitleCacheLimitMB: Int {
        let saved = UserDefaults.standard.integer(forKey: subtitleCacheLimitKey)
        return subtitleCacheLimitOptionsMB.contains(saved) ? saved : defaultSubtitleCacheLimitMB
    }

    static var subtitleCacheLimitBytes: Int64 {
        Int64(subtitleCacheLimitMB) * 1_024 * 1_024
    }

    static func setSubtitleCacheLimitMB(_ value: Int) {
        let safeValue =
            subtitleCacheLimitOptionsMB.contains(value)
            ? value
            : defaultSubtitleCacheLimitMB
        UserDefaults.standard.set(safeValue, forKey: subtitleCacheLimitKey)
        _ = try? pruneSubtitleCache()
    }

    static func subtitleCacheDirectory() throws -> URL {
        guard
            let base = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first
        else {
            throw AirCillerError.subtitlePreparationFailed(
                "macOS no proporcionó una carpeta de caché para el OCR."
            )
        }
        return
            base
            .appendingPathComponent("local.carlosciller.AirCiller", isDirectory: true)
            .appendingPathComponent("SubtitleOCR", isDirectory: true)
    }

    static func snapshot(excluding activeDirectory: URL? = nil) -> AirCillerStorageSnapshot {
        let subtitleBytes = (try? subtitleCacheDirectory()).map(directorySize) ?? 0
        let preparedBytes = directorySize(
            of: preparedMediaDirectories(
                in: FileManager.default.temporaryDirectory,
                excluding: activeDirectory
            )
        )
        return AirCillerStorageSnapshot(
            subtitleCacheBytes: subtitleBytes,
            preparedMediaBytes: preparedBytes,
            subtitleCacheLimitBytes: subtitleCacheLimitBytes
        )
    }

    static func touchCachedSubtitle(_ url: URL) {
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: url.path
        )
    }

    @discardableResult
    static func pruneSubtitleCache() throws -> Int64 {
        let directory = try subtitleCacheDirectory()
        return try pruneFiles(in: directory, limitBytes: subtitleCacheLimitBytes)
    }

    static func clearSubtitleCache() throws {
        let directory = try subtitleCacheDirectory()
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    static func clearPreparedMedia(excluding activeDirectory: URL? = nil) {
        let directories = preparedMediaDirectories(
            in: FileManager.default.temporaryDirectory,
            excluding: activeDirectory
        )
        for directory in directories {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @discardableResult
    static func pruneFiles(in directory: URL, limitBytes: Int64) throws -> Int64 {
        guard limitBytes >= 0,
            FileManager.default.fileExists(atPath: directory.path)
        else { return 0 }
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]
        var files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).compactMap { url -> CachedFile? in
            guard let values = try? url.resourceValues(forKeys: keys),
                values.isRegularFile == true
            else { return nil }
            return CachedFile(
                url: url,
                bytes: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast
            )
        }
        var total = files.reduce(Int64.zero) { $0 + $1.bytes }
        files.sort {
            if $0.modifiedAt == $1.modifiedAt { return $0.url.path < $1.url.path }
            return $0.modifiedAt < $1.modifiedAt
        }
        for file in files where total > limitBytes {
            try FileManager.default.removeItem(at: file.url)
            total -= file.bytes
        }
        return max(0, total)
    }

    static func preparedMediaDirectories(
        in root: URL,
        excluding activeDirectory: URL? = nil
    ) -> [URL] {
        let excludedPath = activeDirectory?.standardizedFileURL.path
        let values = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return (values ?? []).filter { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            return isDirectory
                && isPreparedMediaDirectoryName(url.lastPathComponent)
                && url.standardizedFileURL.path != excludedPath
        }
    }

    static func isPreparedMediaDirectoryName(_ name: String) -> Bool {
        let prefix = "AirCiller-"
        guard name.hasPrefix(prefix) else { return false }
        return UUID(uuidString: String(name.dropFirst(prefix.count))) != nil
    }

    private static func directorySize(of directories: [URL]) -> Int64 {
        directories.reduce(Int64.zero) { $0 + directorySize($1) }
    }

    private static func directorySize(_ directory: URL) -> Int64 {
        guard
            let enumerator = FileManager.default.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            )
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                values.isRegularFile == true
            else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }

    private struct CachedFile {
        let url: URL
        let bytes: Int64
        let modifiedAt: Date
    }
}
