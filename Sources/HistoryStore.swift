import Foundation

enum HistoryStore {
    static let recentKey = "AirCiller.recent.v1"
    static let queueKey = "AirCiller.queue.v1"
    private static let maximumRecentItems = 30

    static func loadRecent(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> [RecentMediaItem] {
        guard let data = defaults.data(forKey: recentKey) else { return [] }
        guard let items = try? JSONDecoder().decode([RecentMediaItem].self, from: data) else {
            defaults.removeObject(forKey: recentKey)
            return []
        }
        let existing = items.filter { fileManager.fileExists(atPath: $0.path) }
        if existing.count != items.count { saveRecent(existing, defaults: defaults) }
        return existing
    }

    static func saveRecent(_ items: [RecentMediaItem], defaults: UserDefaults = .standard) {
        let trimmed = Array(items.prefix(maximumRecentItems))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        defaults.set(data, forKey: recentKey)
    }

    static func loadQueue(
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) -> [QueueMediaItem] {
        guard let data = defaults.data(forKey: queueKey) else { return [] }
        guard let items = try? JSONDecoder().decode([QueueMediaItem].self, from: data) else {
            defaults.removeObject(forKey: queueKey)
            return []
        }
        let existing = items.filter { fileManager.fileExists(atPath: $0.path) }
        if existing.count != items.count { saveQueue(existing, defaults: defaults) }
        return existing
    }

    static func saveQueue(_ items: [QueueMediaItem], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: queueKey)
    }
}
