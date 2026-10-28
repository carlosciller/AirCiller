import Foundation

@main
struct LibraryRecoveryArchiveSmokeTest {
    struct TestFailure: Error { let message: String }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw TestFailure(message: message) }
    }

    static func expect(
        _ expected: LibraryRecoveryArchive.Failure, _ action: () throws -> Void
    ) throws {
        do {
            try action()
            throw TestFailure(message: "Expected \(expected)")
        } catch let failure as LibraryRecoveryArchive.Failure {
            try require(failure == expected, "Expected \(expected), got \(failure)")
        }
    }

    static func main() throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("AirCiller-Recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let archive = LibraryRecoveryArchive(directory: root)
        try require(try archive.read(.queue, slot: .checkpoint) == nil, "Fresh archive is empty")
        let good = Data("[{\"path\":\"/synthetic/movie.mkv\"}]".utf8)
        let bad = Data("broken-json".utf8)
        let date = Date(timeIntervalSince1970: 123)
        for collection in LibraryRecoveryArchive.Collection.allCases {
            try archive.checkpoint(good, collection: collection, now: date)
            try require(
                try archive.read(collection, slot: .checkpoint)?.payload == good,
                "Each collection has an independent checkpoint")
            try archive.preserveIncident(bad, collection: collection, now: date)
            try archive.preserveIncident(bad, collection: collection, now: date.addingTimeInterval(10))
            try require(
                try archive.read(collection, slot: .incident)?.savedAt == date,
                "Repeated failure preserves original bytes and date")
            try archive.checkpoint(Data("[]".utf8), collection: collection)
            try require(
                try archive.read(collection, slot: .checkpoint)?.payload == good,
                "Empty fallback cannot destroy the valid checkpoint")
            try expect(.occupiedIncident) {
                try archive.preserveIncident(Data("second failure".utf8), collection: collection)
            }
        }
        try archive.markResolved(bad, collection: .recent, now: date)
        try archive.checkpoint(Data("new valid data".utf8), collection: .recent)
        try require(
            try archive.read(.recent, slot: .checkpoint)?.payload == Data("new valid data".utf8),
            "Resolved incidents allow a new valid checkpoint")
        for index in 1...3 {
            let failure = Data("failure-\(index)".utf8)
            try archive.preserveIncident(failure, collection: .recent)
            try archive.markResolved(failure, collection: .recent)
        }
        try require(
            try archive.read(.recent, slot: .previousIncident)?.payload == Data("failure-2".utf8),
            "Retention keeps the preceding resolved incident")
        try require(
            try archive.read(.recent, slot: .incident)?.payload == Data("failure-3".utf8),
            "Retention keeps the newest incident")
        try require(
            try FileManager.default.contentsOfDirectory(atPath: root.path).count == 7,
            "Repeated resolved failures use fixed slots")
        let checkpointURL = archive.url(for: .queue, slot: .checkpoint)
        let original = try Data(contentsOf: checkpointURL)
        let replacement = LibraryRecoveryArchive.Record(
            collection: .queue, savedAt: Date(), payload: Data("new data".utf8))
        try expect(.writeFailed) {
            try archive.write(replacement, slot: .checkpoint) { _, _ in
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(ENOSPC))
            }
        }
        try require(try Data(contentsOf: checkpointURL) == original, "Failed write keeps previous record")
        try expect(.permissionDenied) {
            try archive.write(replacement, slot: .checkpoint) { _, _ in
                throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError)
            }
        }
        try require(try Data(contentsOf: checkpointURL) == original, "Permission failure preserves data")
        var bounded = archive
        bounded.maximumRecordBytes = 100
        try expect(.tooLarge) { try bounded.write(replacement, slot: .checkpoint) }
        try expect(.tooLarge) { _ = try bounded.read(.queue, slot: .checkpoint) }
        try require(try Data(contentsOf: checkpointURL) == original, "Bounds do not truncate old data")

        let unknownVersion = try PropertyListSerialization.data(
            fromPropertyList: ["version": 99], format: .binary, options: 0)
        try unknownVersion.write(to: checkpointURL, options: .atomic)
        try expect(.unsupportedVersion(99)) { _ = try archive.read(.queue, slot: .checkpoint) }
        try bad.write(to: checkpointURL, options: .atomic)
        try expect(.malformedRecord) { _ = try archive.read(.queue, slot: .checkpoint) }
        // Malformed recovery records are never silently replaced.
        try bad.write(to: archive.url(for: .queue, slot: .incident), options: .atomic)
        try expect(.malformedRecord) { try archive.preserveIncident(bad, collection: .queue) }
        try expect(.malformedRecord) { try archive.checkpoint(good, collection: .queue) }
        try require(
            try archive.read(.seasons, slot: .checkpoint)?.payload == good,
            "Damage to one collection leaves others available")

        let link = root.appendingPathComponent("linked-archive")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        let unsafeArchive = LibraryRecoveryArchive(directory: link)
        try expect(.unsafeLocation) { _ = try unsafeArchive.read(.recent, slot: .checkpoint) }
        try expect(.unsafeLocation) { try unsafeArchive.write(replacement, slot: .previousIncident) }
        try archive.write(replacement, slot: .previousIncident)
        let reloaded = LibraryRecoveryArchive(directory: root)
        try require(
            try reloaded.read(.queue, slot: .previousIncident) == replacement,
            "Previous incident survives reopening")
        print("Library recovery archive checks: OK")
    }
}
