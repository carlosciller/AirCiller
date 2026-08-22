import Foundation

enum HistoryStore {
    private static let recentKey = "AirCiller.recent.v1"
    private static let queueKey = "AirCiller.queue.v1"
    private static let maximumRecentItems = 30

    static func loadRecent() -> [RecentMediaItem] {
        guard let data = UserDefaults.standard.data(forKey: recentKey),
            let items = try? JSONDecoder().decode([RecentMediaItem].self, from: data)
        else { return [] }
        let existing = items.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.count != items.count { saveRecent(existing) }
        return existing
    }

    static func saveRecent(_ items: [RecentMediaItem]) {
        let trimmed = Array(items.prefix(maximumRecentItems))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        UserDefaults.standard.set(data, forKey: recentKey)
    }

    static func loadQueue() -> [QueueMediaItem] {
        guard let data = UserDefaults.standard.data(forKey: queueKey),
            let items = try? JSONDecoder().decode([QueueMediaItem].self, from: data)
        else { return [] }
        let existing = items.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.count != items.count { saveQueue(existing) }
        return existing
    }

    static func saveQueue(_ items: [QueueMediaItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: queueKey)
    }
}
