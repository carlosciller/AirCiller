import Foundation

/// A choice in the persisted, user-controlled Playlist order, never filename order.
struct SeasonContinuation: Equatable {
    let item: QueueMediaItem
    let position: Double

    static func target(
        seasonID: String, items: [QueueMediaItem], recent: [RecentMediaItem]
    ) -> Self? {
        guard let item = items.first(where: { $0.seasonID == seasonID && $0.watched != true }) else {
            return nil
        }
        return Self(
            item: item,
            position: resumePosition(queued: item, recent: recent.first { $0.path == item.path }))
    }

    /// Match ordinary library playback, including a completed item explicitly marked pending.
    static func resumePosition(queued: QueueMediaItem?, recent: RecentMediaItem?) -> Double {
        let saved =
            (queued?.watched == true || queued?.progress == 1 ? 0 : queued?.lastPosition)
            ?? recent?.lastPosition ?? 0
        return saved.isFinite ? max(0, saved) : 0
    }
}
