import CryptoKit
import Darwin
import Foundation

/// Retains finalized HLS video/audio renditions. Session-specific subtitles and
/// master playlists never enter this cache. Media is immutable after admission;
/// session playlists are independent copies because subtitle alignment edits them.
actor PreparedMediaCache {
    struct Key: Sendable {
        let digest: String
        fileprivate let source: SourceIdentity
        fileprivate let engine: SourceIdentity?
        fileprivate let separateAudio: Bool

        fileprivate var isCurrent: Bool {
            source.isCurrent() && (engine?.isCurrent() ?? true)
        }
    }

    private struct Manifest: Codable {
        let version: Int
        let key: String
        let files: [CachedFile]
    }

    private struct CachedFile: Codable {
        let name: String
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let digest: String?
    }

    fileprivate struct SourceIdentity: Codable, Equatable, Sendable {
        let path: String
        let device: Int32
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64

        init(_ url: URL) throws {
            let url = url.standardizedFileURL
            let attributes = try PreparedMediaCache.regularFile(url)
            guard FileManager.default.isReadableFile(atPath: url.path) else { throw CacheError.invalidFile }
            path = url.path
            device = attributes.st_dev
            inode = attributes.st_ino
            size = attributes.st_size
            modifiedSeconds = Int64(attributes.st_mtimespec.tv_sec)
            modifiedNanoseconds = Int64(attributes.st_mtimespec.tv_nsec)
            changedSeconds = Int64(attributes.st_ctimespec.tv_sec)
            changedNanoseconds = Int64(attributes.st_ctimespec.tv_nsec)
        }

        func isCurrent() -> Bool {
            (try? SourceIdentity(URL(fileURLWithPath: path))) == self
        }
    }

    private enum CacheError: Error {
        case invalidFile
        case invalidDirectory
        case invalidManifest
        case invalidPlaylist
        case changedSource
        case destinationExists
    }

    private static let formatVersion = 1
    private static let maximumFiles = 50_000
    private static let maximumManifestBytes: Int64 = 16 * 1_024 * 1_024
    private static let maximumPlaylistBytes: Int64 = 8 * 1_024 * 1_024
    private let rootDirectory: URL
    private var limitBytes: Int64
    private var hasAppliedBudget = false

    init(rootDirectory: URL, limitBytes: Int64) {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.limitBytes = max(0, limitBytes)
    }

    /// No subtitle identity or resume position: neither changes this HLS base.
    /// The caller supplies a version for the bundled engine and packaging rules.
    nonisolated static func makeKey(
        source: URL,
        probe: MediaProbe,
        audio: AudioTrack?,
        outputMode: AudioOutputMode,
        audioDelay: Double,
        multiplexed: Bool,
        engineVersion: String,
        engineURL: URL? = nil
    ) throws -> Key {
        guard audioDelay.isFinite, probe.duration.isFinite, !engineVersion.isEmpty else {
            throw CacheError.invalidManifest
        }
        let identity = try SourceIdentity(source)
        let engineIdentity = try engineURL.map(SourceIdentity.init)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let sourceData = try encoder.encode(identity)
        let parameters: [String] = [
            String(formatVersion), engineVersion,
            String(probe.videoStreamIndex), probe.videoCodec, probe.videoProfile ?? "",
            String(probe.videoLevel ?? -1), probe.hevcCodecIdentifier ?? "",
            String(probe.width ?? -1), String(probe.height ?? -1), probe.frameRate ?? "",
            probe.colorTransfer ?? "", String(probe.isDolbyVision),
            String(probe.dolbyVisionProfile ?? -1), String(probe.dolbyVisionLevel ?? -1),
            String(probe.dolbyVisionCompatibilityID ?? -1), String(probe.duration.bitPattern),
            String(multiplexed), String(audio?.streamIndex ?? -1), audio?.codec ?? "",
            audio?.profile ?? "", String(audio?.channels ?? -1), audio?.channelLayout ?? "",
            outputMode.rawValue,
            abs(audioDelay) < 0.001
                ? "0" : String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), audioDelay),
        ]
        var data = sourceData
        data.append(try encoder.encode(engineIdentity))
        data.append(try encoder.encode(parameters))
        return Key(
            digest: hash(data), source: identity, engine: engineIdentity, separateAudio: audio != nil && !multiplexed)
    }

    /// Cache corruption and I/O failures are optimization misses, not playback
    /// failures. Cancellation remains observable to the owning preparation task.
    func checkout(key: Key, into directory: URL) throws -> Bool {
        try Task.checkCancellation()
        guard limitBytes > 0, key.isCurrent else { return false }
        var created: [URL] = []
        var staging: URL?
        do {
            try ensureRoot(create: false)
            try Self.requireDirectory(directory)
            let entry = entryURL(key.digest)
            let files = try validatedFiles(in: entry, key: key)
            guard
                try FileManager.default.contentsOfDirectory(atPath: directory.path)
                    .allSatisfy({ !Self.isBaseName($0) })
            else {
                throw CacheError.destinationExists
            }
            // Subtitle extraction may already be writing into this session.
            // Stage only the base files and never replace the whole directory.
            let temporary = directory.appendingPathComponent(".hls-cache-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
            staging = temporary
            for file in files {
                try Task.checkCancellation()
                let source = entry.appendingPathComponent(file.name)
                let target = temporary.appendingPathComponent(file.name)
                if Self.isPlaylist(file.name) {
                    try FileManager.default.copyItem(at: source, to: target)
                } else {
                    try FileManager.default.linkItem(at: source, to: target)
                }
                guard try Self.matches(file, url: target) else { throw CacheError.invalidFile }
            }
            try Task.checkCancellation()
            guard key.isCurrent else { throw CacheError.changedSource }
            for file in files {
                try Task.checkCancellation()
                let target = directory.appendingPathComponent(file.name)
                try FileManager.default.moveItem(at: temporary.appendingPathComponent(file.name), to: target)
                created.append(target)
            }
            try Task.checkCancellation()
            guard key.isCurrent else { throw CacheError.changedSource }
            try? FileManager.default.removeItem(at: temporary)
            staging = nil
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: entry.path)
            return true
        } catch {
            for file in created { try? FileManager.default.removeItem(at: file) }
            if let staging { try? FileManager.default.removeItem(at: staging) }
            if error is CancellationError { throw error }
            return false
        }
    }

    /// Admission must follow the caller's HLS/HDR validation, before any
    /// session-specific subtitle/master work. Never mutate admitted media.
    @discardableResult
    func store(key: Key, from directory: URL) throws -> Bool {
        try Task.checkCancellation()
        guard limitBytes > 0, key.isCurrent else { return false }
        var staging: URL?
        do {
            try ensureRoot(create: true)
            guard try Self.requireDirectory(directory).st_dev == Self.requireDirectory(rootDirectory).st_dev else {
                return false
            }
            let names = try baseNames(in: directory, separateAudio: key.separateAudio)
            var files: [CachedFile] = []
            var bytes: Int64 = 0
            for name in names.sorted() {
                try Task.checkCancellation()
                let file = directory.appendingPathComponent(name)
                let attributes = try Self.regularFile(file)
                guard attributes.st_size > 0, attributes.st_size <= limitBytes - bytes else { return false }
                bytes += attributes.st_size
                files.append(
                    CachedFile(
                        name: name, size: attributes.st_size,
                        modifiedSeconds: Int64(attributes.st_mtimespec.tv_sec),
                        modifiedNanoseconds: Int64(attributes.st_mtimespec.tv_nsec),
                        digest: Self.isPlaylist(name) ? Self.hash(try Self.readPlaylist(file)) : nil
                    )
                )
            }
            let manifest = Manifest(version: Self.formatVersion, key: key.digest, files: files)
            let manifestData = try JSONEncoder().encode(manifest)
            guard manifestData.count <= Self.maximumManifestBytes,
                Int64(manifestData.count) <= limitBytes - bytes
            else { return false }
            bytes += Int64(manifestData.count)
            let entry = entryURL(key.digest)
            if (try? validatedFiles(in: entry, key: key)) != nil {
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: entry.path)
                return true
            }
            if Self.itemExists(entry) { try removeEntry(entry) }

            // An interrupted admission stays in the owning session's temporary
            // directory, which already has bounded lifetime/crash cleanup.
            let temporary = directory.appendingPathComponent(".hls-admission-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
            staging = temporary
            for file in files {
                try Task.checkCancellation()
                let source = directory.appendingPathComponent(file.name)
                let target = temporary.appendingPathComponent(file.name)
                if Self.isPlaylist(file.name) {
                    try FileManager.default.copyItem(at: source, to: target)
                } else {
                    try FileManager.default.linkItem(at: source, to: target)
                }
                guard try Self.matches(file, url: target) else { throw CacheError.invalidFile }
            }
            try manifestData.write(to: temporary.appendingPathComponent("manifest.json"), options: .atomic)
            _ = try validatedFiles(in: temporary, key: key)
            try Task.checkCancellation()
            guard key.isCurrent else { throw CacheError.changedSource }
            _ = try prune(to: limitBytes - bytes)
            try Task.checkCancellation()
            guard key.isCurrent else { throw CacheError.changedSource }
            // Atomic rename never falls back to copying a complete movie if the
            // filesystem layout changes during preparation.
            let moved = temporary.withUnsafeFileSystemRepresentation { source in
                entry.withUnsafeFileSystemRepresentation { destination in
                    guard let source, let destination else { return false }
                    return rename(source, destination) == 0
                }
            }
            guard moved else { throw CacheError.invalidDirectory }
            staging = nil
            return true
        } catch {
            if let staging { try? FileManager.default.removeItem(at: staging) }
            if error is CancellationError { throw error }
            return false
        }
    }

    func setLimitBytes(_ value: Int64) throws {
        let requested = max(0, value)
        guard !hasAppliedBudget || requested != limitBytes else { return }
        limitBytes = requested
        hasAppliedBudget = false
        _ = try prune()
        hasAppliedBudget = true
    }

    /// Removes only the retained entry. A session's existing hard links remain
    /// available until its owner closes that session.
    func invalidate(key: Key) throws {
        try Task.checkCancellation()
        guard Self.itemExists(rootDirectory) else { return }
        try ensureRoot(create: false)
        let entry = entryURL(key.digest)
        if Self.itemExists(entry) { try removeEntry(entry) }
    }

    @discardableResult
    func prune() throws -> Int64 {
        try prune(to: limitBytes)
    }

    func clear() throws {
        _ = try prune(to: 0)
    }

    func sizeBytes() throws -> Int64 {
        try entries().reduce(0) { total, entry in
            guard entry.bytes <= Int64.max - total else { throw CacheError.invalidManifest }
            return total + entry.bytes
        }
    }

    private func prune(to budget: Int64) throws -> Int64 {
        var entries = try entries()
        var total: Int64 = 0
        for entry in entries {
            guard entry.bytes <= Int64.max - total else { throw CacheError.invalidManifest }
            total += entry.bytes
        }
        entries.sort {
            $0.modified == $1.modified ? $0.url.lastPathComponent < $1.url.lastPathComponent : $0.modified < $1.modified
        }
        for entry in entries where total > budget || entry.bytes == 0 {
            try Task.checkCancellation()
            try removeEntry(entry.url)
            total -= entry.bytes
        }
        return total
    }

    private func entries() throws -> [(url: URL, bytes: Int64, modified: Date)] {
        try Task.checkCancellation()
        guard Self.itemExists(rootDirectory) else { return [] }
        try ensureRoot(create: false)
        return try FileManager.default.contentsOfDirectory(
            at: rootDirectory, includingPropertiesForKeys: nil
        ).filter { Self.isEntryName($0.lastPathComponent) }.map { entry in
            try Task.checkCancellation()
            guard (try? Self.requireDirectory(entry)) != nil else {
                return (entry, 0, Date.distantPast)
            }
            let files = try FileManager.default.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)
            var bytes: Int64 = 0
            for file in files {
                try Task.checkCancellation()
                if let attributes = try? Self.regularFile(file) {
                    guard attributes.st_size <= Int64.max - bytes else { throw CacheError.invalidManifest }
                    bytes += attributes.st_size
                }
            }
            let modified =
                (try? entry.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
                ?? .distantPast
            return (entry, bytes, modified)
        }
    }

    private func validatedFiles(in entry: URL, key: Key) throws -> [CachedFile] {
        try Self.requireDirectory(entry)
        let manifestURL = entry.appendingPathComponent("manifest.json")
        let attributes = try Self.regularFile(manifestURL)
        guard attributes.st_size > 0, attributes.st_size <= Self.maximumManifestBytes else {
            throw CacheError.invalidManifest
        }
        let data = try Self.readBounded(manifestURL, maximumBytes: Self.maximumManifestBytes)
        let manifest = try JSONDecoder().decode(Manifest.self, from: data)
        guard manifest.version == Self.formatVersion, manifest.key == key.digest,
            !manifest.files.isEmpty, manifest.files.count <= Self.maximumFiles
        else { throw CacheError.invalidManifest }
        var names = Set<String>()
        for file in manifest.files {
            try Task.checkCancellation()
            guard Self.isBaseName(file.name), names.insert(file.name).inserted,
                file.size > 0, try Self.matches(file, url: entry.appendingPathComponent(file.name))
            else { throw CacheError.invalidManifest }
        }
        guard try baseNames(in: entry, separateAudio: key.separateAudio) == names else {
            throw CacheError.invalidManifest
        }
        return manifest.files
    }

    private func baseNames(in directory: URL, separateAudio: Bool) throws -> Set<String> {
        var names = try playlistNames(in: directory, rendition: "video")
        if separateAudio { names.formUnion(try playlistNames(in: directory, rendition: "audio")) }
        guard names.count <= Self.maximumFiles else { throw CacheError.invalidManifest }
        return names
    }

    private func playlistNames(in directory: URL, rendition: String) throws -> Set<String> {
        let name = "\(rendition).m3u8"
        let data = try Self.readPlaylist(directory.appendingPathComponent(name))
        guard let text = String(data: data, encoding: .utf8) else { throw CacheError.invalidPlaylist }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.first == "#EXTM3U", lines.last == "#EXT-X-ENDLIST",
            lines.contains("#EXT-X-PLAYLIST-TYPE:VOD"),
            lines.contains("#EXT-X-MAP:URI=\"\(rendition)-init.mp4\"")
        else { throw CacheError.invalidPlaylist }
        var names: Set<String> = [name, "\(rendition)-init.mp4"]
        var expectsSegment = false
        var segmentCount = 0
        for line in lines {
            try Task.checkCancellation()
            if line.hasPrefix("#EXTINF:") {
                guard !expectsSegment,
                    let value = line.dropFirst(8).split(separator: ",", omittingEmptySubsequences: false).first,
                    let duration = Double(value),
                    duration.isFinite, duration > 0
                else { throw CacheError.invalidPlaylist }
                expectsSegment = true
            } else if !line.hasPrefix("#") {
                guard expectsSegment, Self.isSegment(line, rendition: rendition), names.insert(line).inserted else {
                    throw CacheError.invalidPlaylist
                }
                segmentCount += 1
                guard names.count <= Self.maximumFiles else { throw CacheError.invalidManifest }
                expectsSegment = false
            } else if line == "#EXTM3U" || line == "#EXT-X-ENDLIST"
                || line == "#EXT-X-PLAYLIST-TYPE:VOD" || line == "#EXT-X-INDEPENDENT-SEGMENTS"
                || line == "#EXT-X-MAP:URI=\"\(rendition)-init.mp4\""
                || line.hasPrefix("#EXT-X-VERSION:") || line.hasPrefix("#EXT-X-TARGETDURATION:")
                || line.hasPrefix("#EXT-X-MEDIA-SEQUENCE:")
            {
                continue
            } else {
                // No remote keys, variant references, byteranges or arbitrary URLs.
                throw CacheError.invalidPlaylist
            }
        }
        guard !expectsSegment, segmentCount > 0 else { throw CacheError.invalidPlaylist }
        return names
    }

    private func ensureRoot(create: Bool) throws {
        if create && !Self.itemExists(rootDirectory) {
            try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        }
        try Self.requireDirectory(rootDirectory)
    }

    private func entryURL(_ digest: String) -> URL {
        rootDirectory.appendingPathComponent(digest, isDirectory: true)
    }

    private func removeEntry(_ entry: URL) throws {
        guard entry.deletingLastPathComponent().standardizedFileURL.path == rootDirectory.path,
            Self.isEntryName(entry.lastPathComponent)
        else { throw CacheError.invalidDirectory }
        // FileManager unlinks symlinks, never follows them when removing items.
        try FileManager.default.removeItem(at: entry)
    }

    private nonisolated static func readPlaylist(_ url: URL) throws -> Data {
        let attributes = try regularFile(url)
        guard attributes.st_size > 0, attributes.st_size <= maximumPlaylistBytes else {
            throw CacheError.invalidPlaylist
        }
        return try readBounded(url, maximumBytes: maximumPlaylistBytes)
    }

    private nonisolated static func readBounded(_ url: URL, maximumBytes: Int64) throws -> Data {
        let descriptor = url.withUnsafeFileSystemRepresentation { pointer in
            pointer.map { open($0, O_RDONLY | O_NOFOLLOW | O_CLOEXEC) } ?? -1
        }
        guard descriptor >= 0 else { throw CacheError.invalidFile }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var attributes = stat()
        guard fstat(descriptor, &attributes) == 0, attributes.st_mode & S_IFMT == S_IFREG,
            attributes.st_size > 0, attributes.st_size <= maximumBytes,
            let data = try handle.read(upToCount: Int(maximumBytes) + 1),
            data.count <= maximumBytes
        else { throw CacheError.invalidFile }
        return data
    }

    private nonisolated static func matches(_ file: CachedFile, url: URL) throws -> Bool {
        let attributes = try regularFile(url)
        guard attributes.st_size == file.size,
            Int64(attributes.st_mtimespec.tv_sec) == file.modifiedSeconds,
            Int64(attributes.st_mtimespec.tv_nsec) == file.modifiedNanoseconds
        else { return false }
        if isPlaylist(file.name) { return file.digest == hash(try readPlaylist(url)) }
        return file.digest == nil
    }

    private nonisolated static func isPlaylist(_ name: String) -> Bool {
        name == "video.m3u8" || name == "audio.m3u8"
    }

    private nonisolated static func isBaseName(_ name: String) -> Bool {
        isPlaylist(name) || name == "video-init.mp4" || name == "audio-init.mp4"
            || isSegment(name, rendition: "video") || isSegment(name, rendition: "audio")
    }

    private nonisolated static func isSegment(_ name: String, rendition: String) -> Bool {
        let prefix = "\(rendition)-"
        guard name.hasPrefix(prefix), name.hasSuffix(".m4s") else { return false }
        let digits = name.dropFirst(prefix.count).dropLast(4)
        return digits.count == 8 && digits.utf8.allSatisfy { (48...57).contains($0) }
    }

    private nonisolated static func isEntryName(_ name: String) -> Bool {
        name.utf8.count == 64 && name.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private nonisolated static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func regularFile(_ url: URL) throws -> stat {
        var attributes = stat()
        guard
            url.withUnsafeFileSystemRepresentation({ pointer in
                pointer.map { lstat($0, &attributes) } ?? -1
            }) == 0, attributes.st_mode & S_IFMT == S_IFREG, attributes.st_size >= 0
        else {
            throw CacheError.invalidFile
        }
        return attributes
    }

    @discardableResult
    private nonisolated static func requireDirectory(_ url: URL) throws -> stat {
        var attributes = stat()
        guard
            url.withUnsafeFileSystemRepresentation({ pointer in
                pointer.map { lstat($0, &attributes) } ?? -1
            }) == 0, attributes.st_mode & S_IFMT == S_IFDIR
        else {
            throw CacheError.invalidDirectory
        }
        return attributes
    }

    private nonisolated static func itemExists(_ url: URL) -> Bool {
        var attributes = stat()
        return url.withUnsafeFileSystemRepresentation { pointer in
            pointer.map { lstat($0, &attributes) == 0 } ?? false
        }
    }
}
