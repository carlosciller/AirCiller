import Foundation

enum HistoryStore {
    static let recentKey = "AirCiller.recent.v1"
    static let queueKey = "AirCiller.queue.v1"
    private static let maximumRecentItems = 30

    static func isAvailable(_ url: URL) -> Bool {
        guard url.isFileURL,
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.resolvingSymlinksInPath().path),
            attributes[.type] as? FileAttributeType == .typeRegular
        else { return false }
        return FileManager.default.isReadableFile(atPath: url.path)
    }

    static func loadRecent(
        defaults: UserDefaults = .standard
    ) -> [RecentMediaItem] {
        guard let data = defaults.data(forKey: recentKey) else { return [] }
        guard let items = try? JSONDecoder().decode([RecentMediaItem].self, from: data) else {
            defaults.removeObject(forKey: recentKey)
            return []
        }
        return items
    }

    static func saveRecent(_ items: [RecentMediaItem], defaults: UserDefaults = .standard) {
        let trimmed = Array(items.prefix(maximumRecentItems))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        defaults.set(data, forKey: recentKey)
    }

    static func loadQueue(
        defaults: UserDefaults = .standard
    ) -> [QueueMediaItem] {
        guard let data = defaults.data(forKey: queueKey) else { return [] }
        guard let items = try? JSONDecoder().decode([QueueMediaItem].self, from: data) else {
            defaults.removeObject(forKey: queueKey)
            return []
        }
        return items
    }

    static func saveQueue(_ items: [QueueMediaItem], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: queueKey)
    }

    /// Relinking is explicit. Never merge two library entries or guess which progress to keep.
    static func relocating(
        from oldURL: URL, to newURL: URL,
        recent: [RecentMediaItem], queue: [QueueMediaItem]
    ) -> (recent: [RecentMediaItem], queue: [QueueMediaItem])? {
        guard recent.contains(where: { $0.path == oldURL.path }) || queue.contains(where: { $0.path == oldURL.path })
        else { return nil }
        if oldURL.path == newURL.path { return (recent, queue) }
        guard !recent.contains(where: { $0.path == newURL.path }),
            !queue.contains(where: { $0.path == newURL.path })
        else { return nil }
        let title = newURL.deletingPathExtension().lastPathComponent
        return (
            recent.map { item in
                guard item.path == oldURL.path else { return item }
                return RecentMediaItem(
                    path: newURL.path, title: title, lastOpened: item.lastOpened,
                    lastPosition: item.lastPosition, duration: item.duration)
            },
            queue.map { item in
                item.path == oldURL.path ? QueueMediaItem(path: newURL.path, title: title) : item
            }
        )
    }
}
