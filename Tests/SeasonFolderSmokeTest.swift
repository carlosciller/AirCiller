import Foundation

@main
struct SeasonFolderSmokeTest {
    static func main() async throws {
        let manager = FileManager.default
        let root = manager.temporaryDirectory.appendingPathComponent("AirCillerSeason-\(UUID())")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: root) }
        for name in ["Episode 10.mkv", "Episode 2.mkv", "Episode 1.MP4", ".hidden.mkv", "notes.txt"] {
            try Data("fixture".utf8).write(to: root.appendingPathComponent(name))
        }
        let extras = root.appendingPathComponent("Extras")
        try manager.createDirectory(at: extras, withIntermediateDirectories: true)
        try Data("extra".utf8).write(to: extras.appendingPathComponent("Interview.mov"))
        try manager.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        let result = try SeasonFolderImporter.scan(root)
        guard
            result.movies.map(\.lastPathComponent) == [
                "Episode 1.MP4", "Episode 2.mkv", "Episode 10.mkv", "Interview.mov",
            ], result.unreadablePaths.isEmpty
        else { throw Failure() }
        let cancelled = Task {
            try Task.checkCancellation()
            return try SeasonFolderImporter.scan(root)
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            throw Failure()
        } catch is CancellationError {}
        let inaccessible = root.appendingPathComponent("Unavailable")
        try manager.createDirectory(at: inaccessible, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: inaccessible.appendingPathComponent("Episode.mkv"))
        try manager.setAttributes([.posixPermissions: 0], ofItemAtPath: inaccessible.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: inaccessible.path) }
        let partial = try SeasonFolderImporter.scan(root)
        let unreadablePaths = partial.unreadablePaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        guard partial.movies.map(\.path) == result.movies.map(\.path),
            unreadablePaths.contains(inaccessible.standardizedFileURL.path)
        else {
            FileHandle.standardError.write(
                Data(
                    "Partial failure fixture: actual=\(partial.movies.map(\.path)), expected=\(result.movies.map(\.path)), unreadable=\(partial.unreadablePaths), expectedUnavailable=\(inaccessible.path)\n"
                        .utf8))
            throw Failure()
        }
        let many = root.appendingPathComponent("Many")
        try manager.createDirectory(at: many, withIntermediateDirectories: true)
        for index in 0..<128 {
            try Data("fixture".utf8).write(to: many.appendingPathComponent("Episode \(index).mkv"))
        }
        let began = DispatchSemaphore(value: 0)
        let resume = DispatchSemaphore(value: 0)
        let running = Task.detached {
            try SeasonFolderImporter.scan(many) { _ in
                began.signal()
                resume.wait()
            }
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !hasStarted(began) {
            guard ContinuousClock.now < deadline else {
                running.cancel()
                resume.signal()
                throw Failure()
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        running.cancel()
        resume.signal()
        do {
            _ = try await running.value
            throw Failure()
        } catch is CancellationError {}
        print(
            "Season folders: numeric order, recursion, extras, hidden files, symlink cycles, partial failures and in-flight cancellation: OK"
        )
    }
    // Nonblocking poll; the scanner's pause itself remains on its detached worker.
    private static func hasStarted(_ semaphore: DispatchSemaphore) -> Bool {
        semaphore.wait(timeout: .now()) == .success
    }
    private struct Failure: Error {}
}
