import Foundation

@main
struct ShortcutsControllerSmokeTest {
    @MainActor
    static func main() async throws {
        // Durable test files live below the checkout, outside the temporary
        // locations that a file-provider shortcut is expressly not allowed to use.
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(".build/tests/shortcuts-\(UUID())")
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixtures) }
        let movie = fixtures.appendingPathComponent("test.mkv")
        try Data([0]).write(to: movie)
        let target = FakeTarget()
        let controller = ShortcutsController(discoveryTimeout: .milliseconds(150))
        try expect(.unavailable) { try controller.pause() }
        controller.register(target)
        try expect(.localFileRequired) { try controller.openMovie(url: nil, removedOnCompletion: false) }
        try expect(.localFileRequired) {
            try controller.addMovie(url: URL(string: "https://example.com/movie.mkv"), removedOnCompletion: false)
        }
        try expect(.localFileRequired) { try controller.addMovie(url: movie, removedOnCompletion: true) }
        try expect(.localFileRequired) {
            try controller.addMovie(url: URL(fileURLWithPath: "/tmp/shortcut.mkv"), removedOnCompletion: false)
        }
        try expect(.unsupportedFile) {
            try controller.addMovie(url: fixtures.appendingPathComponent("test.txt"), removedOnCompletion: false)
        }
        try expect(.unreadableFile) {
            try controller.addMovie(url: fixtures.appendingPathComponent("missing.mkv"), removedOnCompletion: false)
        }
        let directory = fixtures.appendingPathComponent("directory.mkv")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try expect(.unreadableFile) { try controller.addMovie(url: directory, removedOnCompletion: false) }
        let link = fixtures.appendingPathComponent("temporary.mkv")
        let temporaryMovie = FileManager.default.temporaryDirectory.appendingPathComponent("shortcuts-\(UUID()).mkv")
        try Data([0]).write(to: temporaryMovie)
        defer { try? FileManager.default.removeItem(at: temporaryMovie) }
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: temporaryMovie)
        try expect(.localFileRequired) { try controller.addMovie(url: link, removedOnCompletion: false) }
        try require(target.loads == 0 && target.queued.isEmpty, "invalid files never mutate the target")

        try controller.openMovie(url: movie, removedOnCompletion: false)
        try require(target.loads == 1 && !target.autoStart, "open does not start playback")
        target.shortcutsIsBusy = true
        try expect(.busy) { try controller.openMovie(url: movie, removedOnCompletion: false) }
        try controller.addMovie(url: movie, removedOnCompletion: false)
        try controller.addMovie(url: movie, removedOnCompletion: false)
        try require(target.queued == [movie.path] && target.loads == 1, "add is idempotent without loading")
        try expect(.noSession) { try controller.resume() }
        target.shortcutsHasSession = true
        try controller.pause()
        try controller.pause()
        try controller.resume()
        try require(target.commands == ["pause", "pause", "resume"], "explicit commands never toggle or start")
        target.acceptCommands = false
        try expect(.commandRejected) { try controller.pause() }
        try controller.stop()
        try require(target.stops == 1, "stop reaches the existing owner")
        try expect(.noSession) { try controller.pause() }

        let first = ShortcutsDestination(id: "first", name: "First")
        let second = ShortcutsDestination(id: "second", name: "Second")
        try expect(.noDestination) { _ = try ShortcutsController.destination(in: [], name: nil) }
        try expect(.ambiguousDestination) { _ = try ShortcutsController.destination(in: [first, second], name: nil) }
        try expect(.unknownDestination) { _ = try ShortcutsController.destination(in: [first], name: "Other") }
        try expect(.ambiguousDestination) {
            _ = try ShortcutsController.destination(in: [first, .init(id: "duplicate", name: "First")], name: "First")
        }
        try require(
            try ShortcutsController.destination(in: [first, second], name: " Second ") == second,
            "named destination does not depend on discovery order")

        target.shortcutsDestinations = [first]
        try await controller.sendMovie(
            url: movie, removedOnCompletion: false, destinationName: nil, fromBeginning: true)
        try require(target.autoStart && target.fromBeginning && target.destinationID == first.id, "handoff options")
        let oldLoads = target.loads
        target.shortcutsIsDiscovering = true
        let pending = Task {
            try await controller.sendMovie(
                url: movie, removedOnCompletion: false, destinationName: nil, fromBeginning: false)
        }
        try await Task.sleep(for: .milliseconds(20))
        try expect(.busy) { try controller.openMovie(url: movie, removedOnCompletion: false) }
        try controller.stop()
        do {
            try await pending.value
            throw Failure(message: "stopped pending send unexpectedly succeeded")
        } catch ShortcutsFailure.changed {}
        try require(target.loads == oldLoads, "stop cancels pending handoff without loading")

        let cancelled = Task {
            try await controller.sendMovie(
                url: movie, removedOnCompletion: false, destinationName: nil, fromBeginning: false)
        }
        try await Task.sleep(for: .milliseconds(20))
        cancelled.cancel()
        do {
            try await cancelled.value
            throw Failure(message: "canceled send unexpectedly succeeded")
        } catch is CancellationError {}
        try require(target.loads == oldLoads && target.stops == 2, "cancellation does not stop a newer UI movie")

        let changed = Task {
            try await controller.sendMovie(
                url: movie, removedOnCompletion: false, destinationName: nil, fromBeginning: false)
        }
        try await Task.sleep(for: .milliseconds(20))
        target.shortcutsGeneration = UUID()
        do {
            try await changed.value
            throw Failure(message: "stale UI generation unexpectedly succeeded")
        } catch ShortcutsFailure.changed {}
        try require(target.loads == oldLoads, "UI activity invalidates waiting shortcut")
        do {
            try await controller.sendMovie(
                url: movie, removedOnCompletion: false, destinationName: nil, fromBeginning: false)
            throw Failure(message: "stuck discovery unexpectedly succeeded")
        } catch ShortcutsFailure.discoveryTimeout {}

        target.shortcutsIsDiscovering = false
        target.selectionWait = .milliseconds(80)
        let selectionPending = Task {
            try await controller.sendMovie(
                url: movie, removedOnCompletion: false, destinationName: nil, fromBeginning: false)
        }
        try await Task.sleep(for: .milliseconds(20))
        target.shortcutsGeneration = UUID()
        do {
            try await selectionPending.value
            throw Failure(message: "handoff ignored UI activity during authorization lookup")
        } catch ShortcutsFailure.changed {}
        try require(target.loads == oldLoads, "authorization lookup rechecks ownership before loading")
        target.selectionWait = .zero
        target.shortcutsDestinations = []
        target.discovered = first
        try await controller.sendMovie(
            url: movie, removedOnCompletion: false, destinationName: nil, fromBeginning: false)
        try require(target.discoveryCount == 1 && target.loads == oldLoads + 1, "cold discovery before handoff")
        try FileManager.default.removeItem(at: movie)
        try expect(.unreadableFile) { try controller.addMovie(url: movie, removedOnCompletion: false) }
        print("Shortcuts controller: OK (local simulated target; no receiver)")
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message: message) }
    }

    @MainActor
    static func expect(_ error: ShortcutsFailure, _ action: () throws -> Void) throws {
        do {
            try action()
            throw Failure(message: "Expected \(error)")
        } catch let actual as ShortcutsFailure {
            try require(actual == error, "Expected \(error), got \(actual)")
        }
    }

    struct Failure: Error { let message: String }
}

@MainActor
private final class FakeTarget: ShortcutsTarget {
    var shortcutsIsBusy = false
    var shortcutsHasSession = false
    var shortcutsGeneration = UUID()
    var shortcutsReferencedPaths: Set<String> = []
    var shortcutsIsDiscovering = false
    var shortcutsDestinations: [ShortcutsDestination] = []
    var queued: [String] = []
    var commands: [String] = []
    var acceptCommands = true
    var loads = 0
    var stops = 0
    var autoStart = false
    var fromBeginning = false
    var destinationID: String?
    var shortcutsSelectedDestinationID: String? { destinationID }
    var discoveryCount = 0
    var discovered: ShortcutsDestination?
    var selectionWait: Duration = .zero

    func shortcutsBeginDiscovery() {
        discoveryCount += 1
        shortcutsIsDiscovering = true
        Task {
            try? await Task.sleep(for: .milliseconds(20))
            if let discovered { shortcutsDestinations = [discovered] }
            shortcutsIsDiscovering = false
        }
    }
    func shortcutsSelectDestination(id: String) async {
        if selectionWait > .zero { try? await Task.sleep(for: selectionWait) }
        destinationID = id
    }
    func shortcutsLoad(_ url: URL, autoStart: Bool, fromBeginning: Bool) {
        loads += 1
        shortcutsGeneration = UUID()
        shortcutsReferencedPaths.insert(url.path)
        self.autoStart = autoStart
        self.fromBeginning = fromBeginning
    }
    func shortcutsEnqueue(_ url: URL) {
        if !queued.contains(url.path) { queued.append(url.path) }
        shortcutsReferencedPaths.insert(url.path)
    }
    func shortcutsPause() -> Bool {
        commands.append("pause")
        return acceptCommands
    }
    func shortcutsResume() -> Bool {
        commands.append("resume")
        return acceptCommands
    }
    func shortcutsStop() {
        stops += 1
        shortcutsGeneration = UUID()
        shortcutsIsBusy = false
        shortcutsHasSession = false
    }
}
