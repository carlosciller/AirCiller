import Foundation

struct ShortcutsDestination: Equatable {
    let id: String
    let name: String
}

/// The app owns the target. Shortcuts never creates a second playback session.
@MainActor
protocol ShortcutsTarget: AnyObject {
    var shortcutsIsBusy: Bool { get }
    var shortcutsHasSession: Bool { get }
    var shortcutsGeneration: UUID { get }
    var shortcutsReferencedPaths: Set<String> { get }
    var shortcutsIsDiscovering: Bool { get }
    var shortcutsDestinations: [ShortcutsDestination] { get }
    var shortcutsSelectedDestinationID: String? { get }
    func shortcutsBeginDiscovery()
    func shortcutsSelectDestination(id: String) async
    func shortcutsLoad(_ url: URL, autoStart: Bool, fromBeginning: Bool)
    func shortcutsEnqueue(_ url: URL)
    func shortcutsPause() -> Bool
    func shortcutsResume() -> Bool
    func shortcutsStop()
}

enum ShortcutsFailure: String, LocalizedError {
    case unavailable = "Open AirCiller and try again."
    case busy = "AirCiller is already preparing or playing a movie. Stop it before opening another movie."
    case localFileRequired = "Save the movie to a local folder first, then select that file in Shortcuts."
    case unreadableFile = "The movie is missing or unreadable. Check the file and its permissions."
    case unsupportedFile = "Choose an MKV, MP4, M4V, MOV, TS, MTS or M2TS movie."
    case noDestination = "No Apple TV was found. Check that it is awake and on the same network."
    case ambiguousDestination = "More than one Apple TV matches. Enter a unique Apple TV name in this action."
    case unknownDestination = "That Apple TV was not found. Check its name in AirCiller."
    case discoveryTimeout = "Apple TV discovery has not finished. Open AirCiller and try again."
    case changed = "Playback changed while this action was waiting. Nothing was replaced. Run the action again."
    case noSession = "AirCiller has no active playback session. Use Send Movie to Apple TV first."
    case commandRejected = "The playback command could not be sent. Check the connection in AirCiller."

    var errorDescription: String? {
        Bundle.main.localizedString(forKey: rawValue, value: rawValue, table: "Shortcuts")
    }
}

@MainActor
final class ShortcutsController {
    static let shared = ShortcutsController()

    private weak var target: (any ShortcutsTarget)?
    private var pendingSend: UUID?
    private var files: [String: ScopedMovie] = [:]
    private let discoveryTimeout: Duration

    init(discoveryTimeout: Duration = .seconds(12)) {
        self.discoveryTimeout = discoveryTimeout
    }

    func register(_ target: any ShortcutsTarget) {
        if let current = self.target, current !== target {
            pendingSend = nil
            files.removeAll()
        }
        self.target = target
    }

    func openMovie(url: URL?, removedOnCompletion: Bool) throws {
        let target = try availableTarget()
        try requireIdle(target)
        let file = try movie(url: url, removedOnCompletion: removedOnCompletion)
        try Task.checkCancellation()
        target.shortcutsLoad(file.url, autoStart: false, fromBeginning: false)
        retain(file, for: target)
    }

    func addMovie(url: URL?, removedOnCompletion: Bool) throws {
        let target = try availableTarget()
        let file = try movie(url: url, removedOnCompletion: removedOnCompletion)
        try Task.checkCancellation()
        target.shortcutsEnqueue(file.url)
        retain(file, for: target)
    }

    func sendMovie(
        url: URL?, removedOnCompletion: Bool, destinationName: String?, fromBeginning: Bool
    ) async throws {
        let target = try availableTarget()
        try requireIdle(target)
        let file = try movie(url: url, removedOnCompletion: removedOnCompletion)
        let request = UUID()
        let generation = target.shortcutsGeneration
        pendingSend = request
        defer { if pendingSend == request { pendingSend = nil } }

        // Discovery belongs to the app. Canceling a waiting shortcut must not
        // cancel a newer UI action, pairing operation, or shared device scan.
        if target.shortcutsDestinations.isEmpty && !target.shortcutsIsDiscovering {
            target.shortcutsBeginDiscovery()
            await Task.yield()
        }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: discoveryTimeout)
        while target.shortcutsIsDiscovering {
            try verifyRequest(request, generation: generation, target: target)
            guard clock.now < deadline else { throw ShortcutsFailure.discoveryTimeout }
            try await Task.sleep(for: .milliseconds(50))
        }
        try verifyRequest(request, generation: generation, target: target)
        guard !target.shortcutsIsBusy else { throw ShortcutsFailure.busy }
        let destination = try Self.destination(in: target.shortcutsDestinations, name: destinationName)
        await target.shortcutsSelectDestination(id: destination.id)
        try verifyRequest(request, generation: generation, target: target)
        guard !target.shortcutsIsBusy else { throw ShortcutsFailure.busy }
        guard target.shortcutsSelectedDestinationID == destination.id else { throw ShortcutsFailure.changed }
        try file.validate()
        target.shortcutsLoad(file.url, autoStart: true, fromBeginning: fromBeginning)
        retain(file, for: target)
        // Work is now owned by the normal app pipeline, including any explicit
        // pairing or audio conversion prompt. This is not a playback confirmation.
    }

    func pause() throws {
        let target = try availableTarget()
        guard target.shortcutsHasSession else { throw ShortcutsFailure.noSession }
        guard target.shortcutsPause() else { throw ShortcutsFailure.commandRejected }
    }

    func resume() throws {
        let target = try availableTarget()
        guard target.shortcutsHasSession else { throw ShortcutsFailure.noSession }
        guard target.shortcutsResume() else { throw ShortcutsFailure.commandRejected }
    }

    func stop() throws {
        let target = try availableTarget()
        try Task.checkCancellation()
        pendingSend = nil
        target.shortcutsStop()
        prune(for: target)
    }

    static func destination(in devices: [ShortcutsDestination], name: String?) throws -> ShortcutsDestination {
        guard !devices.isEmpty else { throw ShortcutsFailure.noDestination }
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let matches = name.isEmpty ? devices : devices.filter { $0.name == name }
        guard !matches.isEmpty else { throw ShortcutsFailure.unknownDestination }
        guard matches.count == 1, let match = matches.first else { throw ShortcutsFailure.ambiguousDestination }
        return match
    }

    private func availableTarget() throws -> any ShortcutsTarget {
        try Task.checkCancellation()
        guard let target else { throw ShortcutsFailure.unavailable }
        return target
    }

    private func requireIdle(_ target: any ShortcutsTarget) throws {
        guard pendingSend == nil, !target.shortcutsIsBusy else { throw ShortcutsFailure.busy }
    }

    private func verifyRequest(_ id: UUID, generation: UUID, target: any ShortcutsTarget) throws {
        try Task.checkCancellation()
        guard pendingSend == id, target.shortcutsGeneration == generation else { throw ShortcutsFailure.changed }
    }

    private func movie(url: URL?, removedOnCompletion: Bool) throws -> ScopedMovie {
        guard let url, url.isFileURL, !removedOnCompletion else { throw ShortcutsFailure.localFileRequired }
        guard MediaFileTypes.accepts(url) else { throw ShortcutsFailure.unsupportedFile }
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL.path
        let temporaryRoots = [NSTemporaryDirectory(), "/tmp"].map {
            URL(fileURLWithPath: $0).resolvingSymlinksInPath().standardizedFileURL.path
        }
        guard !temporaryRoots.contains(where: { resolved == $0 || resolved.hasPrefix($0 + "/") }) else {
            throw ShortcutsFailure.localFileRequired
        }
        if let existing = files[url.path] {
            try existing.validate()
            return existing
        }
        return try ScopedMovie(url: url)
    }

    private func retain(_ file: ScopedMovie, for target: any ShortcutsTarget) {
        files[file.url.path] = file
        prune(for: target)
    }

    private func prune(for target: any ShortcutsTarget) {
        let retained = target.shortcutsReferencedPaths
        files = files.filter { retained.contains($0.key) }
    }
}

/// Keep security-scoped access alive for asynchronous preparation and playlist
/// replay. No movie data is copied or read into memory by a shortcut.
private final class ScopedMovie {
    let url: URL
    private let scoped: Bool

    init(url: URL) throws {
        self.url = url
        scoped = url.startAccessingSecurityScopedResource()
        try validate()
    }

    func validate() throws {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        guard values?.isRegularFile == true, FileManager.default.isReadableFile(atPath: url.path) else {
            throw ShortcutsFailure.unreadableFile
        }
    }

    deinit {
        if scoped { url.stopAccessingSecurityScopedResource() }
    }
}
