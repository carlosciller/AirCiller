import Foundation

enum HistoryStore {
    static let recentKey = "AirCiller.recent.v1"
    static let queueKey = "AirCiller.queue.v1"
    static let seasonsKey = "AirCiller.seasons.v1"
    static let maximumRecentItems = 30

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
        return Array(items.prefix(maximumRecentItems))
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

    static func loadSeasons(defaults: UserDefaults = .standard) -> [SeasonFolder] {
        guard let data = defaults.data(forKey: seasonsKey),
            let groups = try? JSONDecoder().decode([SeasonFolder].self, from: data)
        else { return [] }
        var seen = Set<String>()
        return groups.filter { seen.insert($0.id).inserted }
    }

    static func saveSeasons(_ groups: [SeasonFolder], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(groups) else { return }
        defaults.set(data, forKey: seasonsKey)
    }

    static func recoveringSeasons(queue: [QueueMediaItem], stored: [SeasonFolder]) -> [SeasonFolder] {
        var groups = stored
        var seen = Set(stored.map(\.id))
        for item in queue {
            guard let path = item.seasonID, path.hasPrefix("/"), seen.insert(path).inserted else { continue }
            groups.append(
                SeasonFolder(path: path, title: URL(fileURLWithPath: path).lastPathComponent, isExpanded: true))
        }
        return groups
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
                guard item.path == oldURL.path else { return item }
                var relocated = item
                relocated.path = newURL.path
                relocated.title = title
                return relocated
            }
        )
    }
}
