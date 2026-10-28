import Foundation

/// Small, local recovery records. Callers serialize access and validate the
/// library payload before offering a restore. This is not the live library.
struct LibraryRecoveryArchive {
    enum Collection: String, Codable, CaseIterable, Sendable {
        case queue, recent, seasons
    }

    enum Slot: String, Sendable {
        case checkpoint, incident, previousIncident
    }

    struct Record: Codable, Equatable, Sendable {
        var version: Int = 1
        var collection: Collection
        var savedAt: Date
        var payload: Data
        var resolvedAt: Date? = nil
    }

    enum Failure: Error, Equatable {
        case tooLarge
        case unsupportedVersion(Int)
        case malformedRecord
        case unsafeLocation
        case permissionDenied
        case readFailed
        case writeFailed
        case occupiedIncident
    }

    // Nine fixed files: three collections, with a checkpoint, first failure and
    // previous-incident record each. At most 36 MiB retained plus one 4 MiB atomic write.
    static let maximumRecordBytes = 4 * 1_024 * 1_024
    let directory: URL
    var maximumRecordBytes = Self.maximumRecordBytes

    func url(for collection: Collection, slot: Slot) -> URL {
        directory.appendingPathComponent("\(collection.rawValue)-\(slot.rawValue).plist")
    }

    func read(_ collection: Collection, slot: Slot) throws -> Record? {
        do {
            try validateDirectory(create: false)
            let file = url(for: collection, slot: slot)
            guard let attributes = try attributesIfPresent(file) else { return nil }
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw Failure.unsafeLocation
            }
            guard let size = attributes[.size] as? NSNumber,
                size.int64Value <= Int64(maximumRecordBytes)
            else { throw Failure.tooLarge }
            let bytes = try Data(contentsOf: file)
            guard bytes.count <= maximumRecordBytes else { throw Failure.tooLarge }
            // Inspect the version independently: a newer schema need not have
            // fields that this version's decoder recognizes.
            guard let plist = try? PropertyListSerialization.propertyList(from: bytes, format: nil),
                let fields = plist as? [String: Any], let version = fields["version"] as? Int
            else { throw Failure.malformedRecord }
            guard version == 1 else { throw Failure.unsupportedVersion(version) }
            guard let record = try? PropertyListDecoder().decode(Record.self, from: bytes),
                record.collection == collection
            else { throw Failure.malformedRecord }
            return record
        } catch let failure as Failure {
            throw failure
        } catch {
            throw classify(error, writing: false)
        }
    }

    /// An unresolved incident is frozen. After explicit recovery, retain the
    /// preceding incident before recording a new one. Only the oldest resolved
    /// incident can age out; the valid checkpoint is a separate file.
    func preserveIncident(_ payload: Data, collection: Collection, now: Date = Date()) throws {
        if var existing = try read(collection, slot: .incident) {
            if existing.payload == payload {
                if existing.resolvedAt != nil {
                    existing.resolvedAt = nil
                    try write(existing, slot: .incident)
                }
                return
            }
            guard existing.resolvedAt != nil else { throw Failure.occupiedIncident }
            // Read before replacement: do not destroy a damaged or newer record.
            if let previous = try read(collection, slot: .previousIncident), previous.resolvedAt == nil {
                throw Failure.occupiedIncident
            }
            try write(existing, slot: .previousIncident)
        }
        try write(Record(collection: collection, savedAt: now, payload: payload), slot: .incident)
    }

    func checkpoint(_ payload: Data, collection: Collection, now: Date = Date()) throws {
        // Never replace the useful checkpoint after a failure, even if a caller
        // attempts to checkpoint the empty fallback or a subsequent session.
        if let incident = try read(collection, slot: .incident), incident.resolvedAt == nil { return }
        if try read(collection, slot: .checkpoint)?.payload == payload { return }
        try write(Record(collection: collection, savedAt: now, payload: payload), slot: .checkpoint)
    }

    func markResolved(_ payload: Data, collection: Collection, now: Date = Date()) throws {
        guard var incident = try read(collection, slot: .incident), incident.payload == payload else {
            throw Failure.occupiedIncident
        }
        incident.resolvedAt = now
        try write(incident, slot: .incident)
    }

    func write(
        _ record: Record, slot: Slot,
        atomicWrite: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) throws {
        guard record.version == 1 else { throw Failure.unsupportedVersion(record.version) }
        guard record.payload.count <= maximumRecordBytes else { throw Failure.tooLarge }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let bytes = try encoder.encode(record)
        guard bytes.count <= maximumRecordBytes else { throw Failure.tooLarge }
        do {
            try validateDirectory(create: true)
            let file = url(for: record.collection, slot: slot)
            if let attributes = try attributesIfPresent(file) {
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw Failure.unsafeLocation
                }
            }
            try atomicWrite(bytes, file)
        } catch let failure as Failure {
            throw failure
        } catch {
            throw classify(error, writing: true)
        }
    }

    private func validateDirectory(create: Bool) throws {
        let manager = FileManager.default
        if let attributes = try attributesIfPresent(directory) {
            guard attributes[.type] as? FileAttributeType == .typeDirectory,
                directory.standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL
            else { throw Failure.unsafeLocation }
        } else if create {
            try manager.createDirectory(
                at: directory, withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            try validateDirectory(create: false)
        }
    }

    private func attributesIfPresent(_ url: URL) throws -> [FileAttributeKey: Any]? {
        do {
            return try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            let failure = error as NSError
            if failure.domain == NSCocoaErrorDomain,
                failure.code == NSFileReadNoSuchFileError || failure.code == NSFileNoSuchFileError
            {
                return nil
            }
            // A failed permission/read check is not evidence of an absent file.
            throw error
        }
    }

    private func classify(_ error: Error, writing: Bool) -> Failure {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain,
            error.code == NSFileReadNoPermissionError || error.code == NSFileWriteNoPermissionError
        {
            return .permissionDenied
        }
        if error.domain == NSPOSIXErrorDomain, error.code == Int(EACCES) || error.code == Int(EPERM) {
            return .permissionDenied
        }
        return writing ? .writeFailed : .readFailed
    }
}
