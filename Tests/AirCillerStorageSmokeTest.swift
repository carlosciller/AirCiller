import Foundation

@main
struct AirCillerStorageSmokeTest {
    static func main() throws {
        try verifyPreparedMediaPreferences()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-Storage-Test-\(UUID().uuidString)", isDirectory: true)
        let cache = root.appendingPathComponent("cache", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let oldest = cache.appendingPathComponent("oldest.vtt")
        let middle = cache.appendingPathComponent("middle.vtt")
        let newest = cache.appendingPathComponent("newest.vtt")
        try Data(repeating: 1, count: 40).write(to: oldest)
        try Data(repeating: 2, count: 40).write(to: middle)
        try Data(repeating: 3, count: 40).write(to: newest)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1)], ofItemAtPath: oldest.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 2)], ofItemAtPath: middle.path)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 3)], ofItemAtPath: newest.path)

        let remaining = try AirCillerStorage.pruneFiles(in: cache, limitBytes: 80)
        let prepared = AirCillerStorage.preparedMediaDirectories(
            in: FileManager.default.temporaryDirectory
        )
        let foundTestDirectory = prepared.contains {
            $0.standardizedFileURL.path == root.standardizedFileURL.path
        }
        guard remaining == 80,
            !FileManager.default.fileExists(atPath: oldest.path),
            FileManager.default.fileExists(atPath: middle.path),
            FileManager.default.fileExists(atPath: newest.path),
            !foundTestDirectory,
            AirCillerStorage.isPreparedMediaDirectoryName("AirCiller-\(UUID().uuidString)"),
            !AirCillerStorage.isPreparedMediaDirectoryName("AirCiller-PythonCache"),
            !AirCillerStorage.isPreparedMediaDirectoryName("AirCiller-SubtitleOCR-Test"),
            !AirCillerStorage.isPreparedMediaDirectoryName("AirCiller-Downloads")
        else {
            throw NSError(
                domain: "AirCillerStorageSmokeTest",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "remaining=\(remaining), oldest=\(FileManager.default.fileExists(atPath: oldest.path)), includedTestDirectory=\(foundTestDirectory)"
                ]
            )
        }
        print("Bounded subtitle cache and removable prepared-media storage: OK")
    }

    private static func verifyPreparedMediaPreferences() throws {
        let name = "AirCiller-Storage-Preferences-\(UUID())"
        guard let defaults = UserDefaults(suiteName: name) else {
            throw NSError(domain: "AirCillerStorageSmokeTest.Preferences", code: 1)
        }
        defer { defaults.removePersistentDomain(forName: name) }
        guard AirCillerStorage.preparedMediaCacheLimitGiB(in: defaults) == 16 else {
            throw NSError(domain: "AirCillerStorageSmokeTest.Default", code: 2)
        }
        for limit in [0, 4, 16, 32, 64] {
            guard AirCillerStorage.savePreparedMediaCacheLimitGiB(limit, in: defaults) == limit,
                AirCillerStorage.preparedMediaCacheLimitGiB(in: defaults) == limit
            else { throw NSError(domain: "AirCillerStorageSmokeTest.ValidLimit", code: 3) }
        }
        for limit in [-1, 1, 65, Int.max] {
            guard AirCillerStorage.savePreparedMediaCacheLimitGiB(limit, in: defaults) == 16,
                AirCillerStorage.preparedMediaCacheLimitGiB(in: defaults) == 16
            else { throw NSError(domain: "AirCillerStorageSmokeTest.InvalidLimit", code: 4) }
        }
        defaults.set("damaged", forKey: "preparedHLSCacheLimitGiB")
        guard AirCillerStorage.preparedMediaCacheLimitGiB(in: defaults) == 16,
            defaults.object(forKey: "subtitleOCRCacheLimitMB") == nil,
            AirCillerStorage.preparedMediaCacheDirectory().lastPathComponent == "PreparedHLS",
            AirCillerStorage.preparedMediaCacheDirectory().deletingLastPathComponent().lastPathComponent
                == "local.carlosciller.AirCiller"
        else { throw NSError(domain: "AirCillerStorageSmokeTest.Isolation", code: 5) }
        print("HLS cache preferences: default 16 GiB, explicit Off, valid limits and isolated OCR setting: OK")
    }
}
