import Foundation

@main
struct StorageRecoverySmokeTest {
    static func main() throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("AirCiller-Storage-Recovery-\(UUID())")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }

        let active = try fixtureDirectory(in: root, name: "AirCiller-\(UUID())")
        let activeAlias = root.appendingPathComponent("active-alias")
        try manager.createSymbolicLink(at: activeAlias, withDestinationURL: active)
        let removable = try fixtureDirectory(in: root, name: "AirCiller-\(UUID())")
        let unrelated = try fixtureDirectory(in: root, name: "AirCiller-Downloads")
        let similarlyNamedFile = root.appendingPathComponent("AirCiller-\(UUID())")
        try Data("Not a prepared directory".utf8).write(to: similarlyNamedFile)
        let denied = root.appendingPathComponent("AirCiller-\(UUID())")
        try manager.createDirectory(at: denied, withIntermediateDirectories: true)
        try Data("Synthetic cache fixture".utf8).write(to: denied.appendingPathComponent("clip.m4s"))
        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: denied.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path) }

        var reportedFailure = false
        do {
            try AirCillerStorage.clearPreparedMedia(in: root, excluding: activeAlias)
        } catch {
            reportedFailure = true
        }
        let retained = manager.fileExists(atPath: denied.appendingPathComponent("clip.m4s").path)
        guard reportedFailure, retained else {
            throw NSError(
                domain: "StorageRecoverySmokeTest", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Refused deletion: reportedFailure=\(reportedFailure), retained=\(retained)"
                ]
            )
        }
        print("Refused temporary-cache deletion is surfaced: OK")

        precondition(!manager.fileExists(atPath: removable.path), "Other removable directories must still be cleared")
        precondition(manager.fileExists(atPath: active.appendingPathComponent("clip.m4s").path))
        precondition(manager.fileExists(atPath: unrelated.appendingPathComponent("clip.m4s").path))
        precondition(manager.fileExists(atPath: similarlyNamedFile.path))
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: denied.path)
        try AirCillerStorage.clearPreparedMedia(in: root, excluding: active)
        precondition(!manager.fileExists(atPath: denied.path), "Retry must remove the previously refused fixture")
        precondition(manager.fileExists(atPath: active.appendingPathComponent("clip.m4s").path))
        try expectFailure {
            try AirCillerStorage.clearPreparedMedia(in: root.appendingPathComponent("unavailable-root"))
        }
        print("Partial cleanup, retry, active-session/alias exclusion, unrelated files and failed enumeration: OK")

        try verifySubtitleCache(in: root)
        verifyPreparedCacheState()
        verifyCleanupAvailability()
    }

    private static func verifySubtitleCache(in root: URL) throws {
        let manager = FileManager.default
        let directory = try fixtureDirectory(in: root, name: "SubtitleOCR")
        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        try expectFailure { try AirCillerStorage.clearSubtitleCache(in: directory) }
        precondition(manager.fileExists(atPath: directory.appendingPathComponent("clip.m4s").path))
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try AirCillerStorage.clearSubtitleCache(in: directory)
        precondition(!manager.fileExists(atPath: directory.path))
        try AirCillerStorage.clearSubtitleCache(in: directory)
        print("Subtitle-cache clear failure, retry and already-empty result: OK")
    }

    private static func verifyPreparedCacheState() {
        var state = PreparedCacheSettingsState()
        precondition(state.sizeBytes == nil && !state.sizeReadFailed && state.operationFailure == nil)
        state.failedToReadSize()
        precondition(state.sizeBytes == nil && state.sizeReadFailed)
        state.receivedSize(512)
        precondition(state.sizeBytes == 512 && !state.sizeReadFailed)

        state.beginOperation()
        state.failedOperation(.clear)
        state.receivedSize(256)
        precondition(state.sizeBytes == 256 && state.operationFailure == .clear && !state.sizeReadFailed)
        state.failedToReadSize()
        precondition(state.sizeReadFailed && state.operationFailure == .clear)
        state.beginOperation()
        precondition(state.operationFailure == nil && state.sizeReadFailed)
        state.receivedSize(0)
        precondition(state.sizeBytes == 0 && !state.sizeReadFailed && state.operationFailure == nil)

        state.beginOperation()
        state.failedOperation(.trim)
        state.receivedSize(128)
        precondition(state.operationFailure == .trim && !state.sizeReadFailed)
        state.beginOperation()
        state.receivedSize(64)
        precondition(state.operationFailure == nil && state.sizeBytes == 64)
        print("Cache-size recovery clears stale read errors, retains clear/trim failures and permits retry: OK")
    }

    private static func fixtureDirectory(in root: URL, name: String) throws -> URL {
        let directory = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("Synthetic cache fixture".utf8).write(to: directory.appendingPathComponent("clip.m4s"))
        return directory
    }

    private static func verifyCleanupAvailability() {
        for bytes: Int64? in [nil, 0, 128] {
            for previousFailure in [false, true] {
                precondition(
                    !CacheCleanupAvailability.canClear(
                        reportedBytes: bytes, previousFailure: previousFailure, busy: true)
                )
                let available = CacheCleanupAvailability.canClear(
                    reportedBytes: bytes, previousFailure: previousFailure, busy: false)
                precondition(available == (bytes != 0 || previousFailure))
            }
        }
        precondition(CacheCleanupAvailability.canClear(reportedBytes: 0, previousFailure: true, busy: false))
        print("Cleanup retry stays available after failed reads report zero, while busy sessions remain protected: OK")
    }

    private static func expectFailure(_ operation: () throws -> Void) throws {
        do {
            try operation()
        } catch {
            return
        }
        throw NSError(domain: "StorageRecoverySmokeTest.ExpectedFailure", code: 2)
    }
}
