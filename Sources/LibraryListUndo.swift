import Foundation

/// Reverses membership and order without replacing the current values of surviving entries.
/// Playback may update Recents between a library action and Undo.
struct LibraryListUndo<Item: Identifiable> {
    private let order: [Item.ID]
    private let restoredItems: [Item]
    private let removedIDs: Set<Item.ID>

    init?(before: [Item], after: [Item]) {
        let beforeIDs = before.map(\.id)
        let afterIDs = after.map(\.id)
        guard beforeIDs != afterIDs else { return nil }
        let afterIDSet = Set(afterIDs)
        order = beforeIDs
        restoredItems = before.filter { !afterIDSet.contains($0.id) }
        removedIDs = Set(afterIDs).subtracting(beforeIDs)
    }

    private init(order: [Item.ID], restoredItems: [Item], removedIDs: Set<Item.ID>) {
        self.order = order
        self.restoredItems = restoredItems
        self.removedIDs = removedIDs
    }

    func applying(to current: [Item], maximumCount: Int? = nil) -> [Item] {
        var result = current.filter { !removedIDs.contains($0.id) }
        var existingIDs = Set(result.map(\.id))
        for item in restoredItems where existingIDs.insert(item.id).inserted {
            // A bounded recent history reserves space for all newer current entries first.
            // Older removed entries remain removed if new openings have filled its limit.
            if let maximumCount, result.count >= maximumCount { break }
            result.append(item)
        }

        // Entries added since the action keep their slots; only the remembered IDs reorder.
        let orderedIDs = Set(order)
        let indices = result.indices.filter { orderedIDs.contains(result[$0].id) }
        let orderedItems = order.compactMap { id in result.first { $0.id == id } }
        // Malformed persisted duplicate IDs must never make Undo index beyond its array.
        guard indices.count == orderedItems.count else { return result }
        for (index, item) in zip(indices, orderedItems) {
            result[index] = item
        }
        return result
    }

    func inverse(in current: [Item]) -> Self {
        // Redo reverses the action, even if playback already re-added a removed recent entry.
        Self(
            order: current.map(\.id),
            restoredItems: current.filter { removedIDs.contains($0.id) },
            removedIDs: Set(restoredItems.map(\.id))
        )
    }
}
