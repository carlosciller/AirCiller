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
        let linkedURL = root.appendingPathComponent("linked.mkv")
        try FileManager.default.createSymbolicLink(at: linkedURL, withDestinationURL: existingURL)
        guard HistoryStore.isAvailable(existingURL), HistoryStore.isAvailable(linkedURL),
            !HistoryStore.isAvailable(missingURL), !HistoryStore.isAvailable(root)
        else { throw NSError(domain: "HistoryStoreSmokeTest.Availability", code: 11) }

        HistoryStore.saveQueue(
            [
                QueueMediaItem(path: existingURL.path, title: "Movie"),
                QueueMediaItem(path: missingURL.path, title: "Missing"),
            ],
            defaults: defaults
        )
        let queueData = defaults.data(forKey: HistoryStore.queueKey)
        let queue = HistoryStore.loadQueue(defaults: defaults)
        guard queue.map(\.path) == [existingURL.path, missingURL.path],
            defaults.data(forKey: HistoryStore.queueKey) == queueData
        else {
            throw NSError(domain: "HistoryStoreSmokeTest.OfflineQueue", code: 2)
        }

        let offlineRecent = RecentMediaItem(
            path: missingURL.path, title: "Missing", lastOpened: Date(timeIntervalSince1970: 100),
            lastPosition: 420, duration: 1800)
        HistoryStore.saveRecent([offlineRecent], defaults: defaults)
        let recentBeforeLoad = defaults.data(forKey: HistoryStore.recentKey)
        guard HistoryStore.loadRecent(defaults: defaults) == [offlineRecent],
            defaults.data(forKey: HistoryStore.recentKey) == recentBeforeLoad
        else { throw NSError(domain: "HistoryStoreSmokeTest.OfflineRecent", code: 5) }

        // Returning storage does not require rebuilding either list or losing progress.
        _ = FileManager.default.createFile(atPath: missingURL.path, contents: Data())
        guard HistoryStore.loadQueue(defaults: defaults) == queue,
            HistoryStore.loadRecent(defaults: defaults) == [offlineRecent]
        else { throw NSError(domain: "HistoryStoreSmokeTest.Reconnect", code: 6) }

        let movedURL = root.appendingPathComponent("renamed.mkv")
        try FileManager.default.moveItem(at: missingURL, to: movedURL)
        guard !HistoryStore.isAvailable(missingURL), HistoryStore.isAvailable(movedURL) else {
            throw NSError(domain: "HistoryStoreSmokeTest.FreshAvailability", code: 12)
        }
        guard
            let moved = HistoryStore.relocating(
                from: missingURL, to: movedURL, recent: [offlineRecent], queue: queue),
            moved.queue.map(\.path) == [existingURL.path, movedURL.path],
            moved.recent.first?.lastPosition == offlineRecent.lastPosition,
            moved.recent.first?.duration == offlineRecent.duration,
            moved.recent.first?.lastOpened == offlineRecent.lastOpened,
            moved.recent.first?.title == "renamed",
            moved.queue.first == queue.first
        else { throw NSError(domain: "HistoryStoreSmokeTest.Relocation", code: 7) }
        HistoryStore.saveQueue(moved.queue, defaults: defaults)
        HistoryStore.saveRecent(moved.recent, defaults: defaults)
        guard HistoryStore.loadQueue(defaults: defaults) == moved.queue,
            HistoryStore.loadRecent(defaults: defaults) == moved.recent,
            FileManager.default.fileExists(atPath: movedURL.path)
        else { throw NSError(domain: "HistoryStoreSmokeTest.ReloadRelocation", code: 8) }

        guard HistoryStore.relocating(from: missingURL, to: existingURL, recent: [offlineRecent], queue: queue) == nil,
            HistoryStore.relocating(from: movedURL, to: missingURL, recent: [offlineRecent], queue: queue) == nil,
            HistoryStore.relocating(from: missingURL, to: missingURL, recent: [offlineRecent], queue: queue)?.queue
                == queue,
            HistoryStore.relocating(from: missingURL, to: movedURL, recent: [offlineRecent], queue: [])?.recent.first?
                .path == movedURL.path,
            HistoryStore.relocating(from: missingURL, to: movedURL, recent: [], queue: queue)?.queue.last?.path
                == movedURL.path
        else { throw NSError(domain: "HistoryStoreSmokeTest.RelocationBoundaries", code: 9) }

        var episode = queue[1]
        episode.seasonID = root.path
        episode.lastPosition = 42
        episode.duration = 120
        episode.watched = true
        let season = SeasonFolder(path: root.path, title: "Season 1", isExpanded: false)
        HistoryStore.saveSeasons([season, season], defaults: defaults)
        guard HistoryStore.loadSeasons(defaults: defaults) == [season] else {
            throw NSError(domain: "HistoryStoreSmokeTest.SeasonDuplicates", code: 13)
        }
        defaults.set(Data("not-json".utf8), forKey: HistoryStore.seasonsKey)
        let recovered = HistoryStore.recoveringSeasons(
            queue: [episode], stored: HistoryStore.loadSeasons(defaults: defaults))
        guard recovered.count == 1, recovered[0].id == root.path,
            recovered[0].isExpanded,
            HistoryStore.loadQueue(defaults: defaults) == moved.queue
        else { throw NSError(domain: "HistoryStoreSmokeTest.SeasonRecovery", code: 14) }
        guard
            let relocatedEpisode = HistoryStore.relocating(
                from: episode.url, to: movedURL, recent: [], queue: [episode])?.queue.first,
            relocatedEpisode.seasonID == episode.seasonID,
            relocatedEpisode.lastPosition == episode.lastPosition,
            relocatedEpisode.duration == episode.duration,
            relocatedEpisode.watched == episode.watched
        else { throw NSError(domain: "HistoryStoreSmokeTest.EpisodeRelocation", code: 15) }

        defaults.set(Data("not-json".utf8), forKey: HistoryStore.queueKey)
        guard HistoryStore.loadQueue(defaults: defaults).isEmpty,
            defaults.data(forKey: HistoryStore.queueKey) == Data("not-json".utf8)
        else { throw NSError(domain: "HistoryStoreSmokeTest.QueueCorruption", code: 10) }

        defaults.set(Data("not-json".utf8), forKey: HistoryStore.recentKey)
        guard HistoryStore.loadRecent(defaults: defaults).isEmpty,
            defaults.data(forKey: HistoryStore.recentKey) == Data("not-json".utf8)
        else {
            throw NSError(domain: "HistoryStoreSmokeTest.Corruption", code: 3)
        }

        HistoryStore.saveQueue([], defaults: defaults)
        HistoryStore.saveRecent([], defaults: defaults)
        HistoryStore.saveSeasons([], defaults: defaults)
        for key in [HistoryStore.queueKey, HistoryStore.recentKey, HistoryStore.seasonsKey] {
            guard defaults.data(forKey: key) == Data("not-json".utf8) else {
                throw NSError(domain: "HistoryStoreSmokeTest.RefuseCorruptOverwrite", code: 16)
            }
        }
        // The following independent limit scenario starts with valid storage.
        defaults.set(Data("[]".utf8), forKey: HistoryStore.recentKey)
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
            try JSONDecoder().decode([RecentMediaItem].self, from: recentData) == Array(recent.prefix(30)),
            HistoryStore.loadRecent(defaults: defaults) == Array(recent.prefix(30))
        else {
            throw NSError(domain: "HistoryStoreSmokeTest.Limit", code: 4)
        }

        // Older or externally restored preferences must not reintroduce an
        // oversized live list before the next save.
        defaults.set(try JSONEncoder().encode(recent), forKey: HistoryStore.recentKey)
        guard HistoryStore.loadRecent(defaults: defaults) == Array(recent.prefix(30)) else {
            throw NSError(domain: "HistoryStoreSmokeTest.LoadLimit", code: 13)
        }

        print("Offline library entries, saved progress, explicit relocation, duplicates and corrupt storage: OK")
    }
}
