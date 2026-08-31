import Foundation

@main
struct HistoryStoreSmokeTest {
    static func main() throws {
        let suite = "AirCiller.HistoryStoreSmokeTest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw NSError(domain: "HistoryStoreSmokeTest.Defaults", code: 1)
        }
        defer { defaults.removePersistentDomain(forName: suite) }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-History-Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let existingURL = root.appendingPathComponent("movie.mkv")
        _ = FileManager.default.createFile(atPath: existingURL.path, contents: Data())
        let missingURL = root.appendingPathComponent("missing.mkv")

        HistoryStore.saveQueue(
            [
                QueueMediaItem(path: existingURL.path, title: "Movie"),
                QueueMediaItem(path: missingURL.path, title: "Missing"),
            ],
            defaults: defaults
        )
        let queue = HistoryStore.loadQueue(defaults: defaults)
        guard queue.map(\.path) == [existingURL.path],
            let repairedData = defaults.data(forKey: HistoryStore.queueKey),
            try JSONDecoder().decode([QueueMediaItem].self, from: repairedData).count == 1
        else {
            throw NSError(domain: "HistoryStoreSmokeTest.Filter", code: 2)
        }

        defaults.set(Data("not-json".utf8), forKey: HistoryStore.recentKey)
        guard HistoryStore.loadRecent(defaults: defaults).isEmpty,
            defaults.object(forKey: HistoryStore.recentKey) == nil
        else {
            throw NSError(domain: "HistoryStoreSmokeTest.Corruption", code: 3)
        }

        let recent = (0..<35).map { index in
            RecentMediaItem(
                path: existingURL.path + "-\(index)",
                title: "Movie \(index)",
                lastOpened: Date(),
                lastPosition: 0,
                duration: 100
            )
        }
        HistoryStore.saveRecent(recent, defaults: defaults)
        guard let recentData = defaults.data(forKey: HistoryStore.recentKey),
            try JSONDecoder().decode([RecentMediaItem].self, from: recentData).count == 30
        else {
            throw NSError(domain: "HistoryStoreSmokeTest.Limit", code: 4)
        }

        print("Corrupt history resets safely and missing files are removed from persistence: OK")
    }
}
