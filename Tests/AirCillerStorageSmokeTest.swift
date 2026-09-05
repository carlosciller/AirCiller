import Foundation

@main
struct AirCillerStorageSmokeTest {
    static func main() throws {
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
}
