import Foundation

@main
struct LibraryListUndoSmokeTest {
    @MainActor
    static func main() throws {
        let a = recent("a", position: 10)
        let b = recent("b", position: 20)
        let c = recent("c", position: 30)
        let extra = recent("new", position: 40)
        let manager = UndoManager()
        manager.groupsByEvent = false
        let store = LibraryUndoTestStore(items: [a, b, c], selection: b.id, manager: manager)

        store.change(to: [a, c], selection: c.id, name: "Remove from Recents")
        try require(manager.canUndo && manager.undoActionName == "Remove from Recents", "native named action")
        store.items[1].lastPosition = 55
        manager.undo()
        try require(store.items.map(\.id) == [a.id, b.id, c.id], "removal order")
        try require(store.selection == b.id && store.items[2].lastPosition == 55, "selection and newer progress")
        manager.redo()
        try require(store.items.map(\.id) == [a.id, c.id] && store.selection == c.id, "native redo")
        manager.undo()
        try require(store.items[2].lastPosition == 55, "progress through repeated undo")

        manager.removeAllActions()
        store.items = [a, b]
        store.selection = a.id
        store.change(to: [], selection: nil, name: "Clear history")
        // The receiver's next progress update may re-add the playing movie before Undo.
        store.items = [extra, recent("a", position: 72)]
        manager.undo()
        try require(store.items.map(\.id) == [extra.id, a.id, b.id], "clear keeps newly opened movie")
        try require(store.items[1].lastPosition == 72 && store.items[2] == b, "clear preserves live and saved values")
        try require(store.selection == a.id, "clear restores selected entry")
        store.items[1].lastPosition = 81
        store.items[0].lastPosition = 88
        manager.redo()
        try require(
            store.items.map(\.id) == [extra.id] && store.items[0].lastPosition == 88, "redo removes only original IDs")
        manager.undo()
        try require(store.items.first { $0.id == a.id }?.lastPosition == 81, "redo captures freshest removed values")
        try require(store.items.first { $0.id == extra.id }?.lastPosition == 88, "unrelated progress survives")

        let fullHistory = (0..<HistoryStore.maximumRecentItems).map { recent("history-\($0)", position: Double($0)) }
        var latestActive = fullHistory[fullHistory.count - 1]
        latestActive.lastPosition = 640
        guard let clearUndo = LibraryListUndo(before: fullHistory, after: [RecentMediaItem]()) else {
            throw Failure(message: "bounded clear undo missing")
        }
        let boundedRestore = clearUndo.applying(
            to: [extra, latestActive], maximumCount: HistoryStore.maximumRecentItems)
        try require(boundedRestore.count == HistoryStore.maximumRecentItems, "recent limit after clear undo")
        try require(boundedRestore.first == extra, "new opening retained at recent limit")
        try require(boundedRestore.last == latestActive, "latest active progress retained even at old tail")
        try require(
            !boundedRestore.contains { $0.id == fullHistory[28].id }, "old removed entry yields to current entries")
        let suite = "AirCiller.LibraryListUndoSmokeTest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { throw Failure(message: "isolated defaults") }
        defer { defaults.removePersistentDomain(forName: suite) }
        HistoryStore.saveRecent(boundedRestore, defaults: defaults)
        try require(
            HistoryStore.loadRecent(defaults: defaults) == boundedRestore, "bounded memory and persistence agree")

        manager.removeAllActions()
        store.items = [a, b, c]
        store.selection = b.id
        store.change(to: [b, a, c], selection: b.id, name: "Reorder playlist")
        store.items.insert(extra, at: 1)
        store.items[2].title = "Updated metadata"
        manager.undo()
        try require(store.items.map(\.id) == [a.id, extra.id, b.id, c.id], "reorder preserves newly added slot")
        try require(
            store.items[0].title == "Updated metadata" && store.selection == b.id, "reorder preserves values and focus")
        manager.redo()
        try require(store.items.map(\.id) == [b.id, extra.id, a.id, c.id], "reorder redo")

        let queue = [a, b, c].map { QueueMediaItem(path: $0.path, title: $0.title) }
        let moved = QueueOrdering.moving(queue, fromOffsets: IndexSet(integer: 2), toOffset: 0)
        guard let queueUndo = LibraryListUndo(before: queue, after: moved) else {
            throw Failure(message: "queue move did not register")
        }
        try require(queueUndo.applying(to: moved) == queue, "real queue move reverses")
        try require(LibraryListUndo(before: queue, after: queue) == nil, "no-op has no undo action")

        // Relocation invalidates this library's actions, not text editing on the same manager.
        let textOwner = TextUndoTestOwner()
        manager.beginUndoGrouping()
        manager.registerUndo(withTarget: textOwner) { target in target.didUndo = true }
        manager.endUndoGrouping()
        manager.removeAllActions(withTarget: store)
        try require(manager.canUndo, "target-only invalidation retains text actions")
        manager.undo()
        try require(textOwner.didUndo && !manager.canUndo, "unrelated native text undo remains usable")

        let missing = recent("unavailable", position: 420)
        guard let offlineUndo = LibraryListUndo(before: [missing], after: [RecentMediaItem]()) else {
            throw Failure(message: "offline undo missing")
        }
        try require(offlineUndo.applying(to: []) == [missing], "unavailable paths restore without file access")
        // Corrupt duplicate identity input must remain safe to process.
        if let duplicateUndo = LibraryListUndo(before: [a, a, b], after: [b]) {
            _ = duplicateUndo.applying(to: [b])
        }
        print(
            "Library Undo/Redo: membership, order, selection, active progress, new entries and target-only invalidation OK"
        )
    }

    private static func recent(_ name: String, position: Double) -> RecentMediaItem {
        RecentMediaItem(
            path: "/synthetic-library/\(name).mkv", title: name,
            lastOpened: Date(timeIntervalSince1970: position), lastPosition: position, duration: 900)
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(message: message) }
    }

    private struct Failure: Error { let message: String }
}

@MainActor
private final class LibraryUndoTestStore {
    var items: [RecentMediaItem]
    var selection: String?
    let manager: UndoManager

    init(items: [RecentMediaItem], selection: String?, manager: UndoManager) {
        self.items = items
        self.selection = selection
        self.manager = manager
    }

    func change(to newItems: [RecentMediaItem], selection newSelection: String?, name: String) {
        guard let edit = LibraryListUndo(before: items, after: newItems) else { return }
        manager.beginUndoGrouping()
        register(edit, selection: selection, name: name)
        items = newItems
        selection = newSelection
        manager.endUndoGrouping()
    }

    private func register(_ edit: LibraryListUndo<RecentMediaItem>, selection: String?, name: String) {
        manager.registerUndo(withTarget: self) { store in
            MainActor.assumeIsolated { store.apply(edit, selection: selection, name: name) }
        }
        manager.setActionName(name)
    }

    private func apply(_ edit: LibraryListUndo<RecentMediaItem>, selection newSelection: String?, name: String) {
        register(edit.inverse(in: items), selection: selection, name: name)
        items = edit.applying(to: items, maximumCount: HistoryStore.maximumRecentItems)
        selection = newSelection.flatMap { id in items.contains { $0.id == id } ? id : nil }
    }
}

@MainActor
private final class TextUndoTestOwner {
    var didUndo = false
}
