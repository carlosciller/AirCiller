import Foundation

enum EpisodePresentationCheck {
    @MainActor static func run() throws {
        let filename = "Example.Show.S01E01.Let.You.Down.1080p.BluRay.Remux.DTS-HD.MA.5.1.mkv"
        let base = URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent
        precondition(EpisodePresentation.title(from: base) == "S01E01 · Let You Down")
        precondition(
            EpisodePresentation.title(from: "Example.Show.S01E02.Like.a.Boy.1080p.BluRay") == "S01E02 · Like a Boy")
        for unknown in [
            "Movie.2026.1080p.BluRay", "Show.S01E01E02.Double.1080p.BluRay",
            "Show.S01E01.S01E02.Double.1080p.BluRay", "Episode 1", "Show.S01E01.Some.Name.Unknown.Release",
        ] { precondition(EpisodePresentation.title(from: unknown) == nil) }
        let original = QueueMediaItem(
            path: "/synthetic-names/" + filename, title: base, seasonID: "/synthetic-names",
            lastPosition: 42, duration: 900, watched: true)
        precondition(original.displayTitle == "S01E01 · Let You Down")
        var standalone = original
        standalone.seasonID = nil
        precondition(standalone.displayTitle == base)
        standalone.title = "Previously chosen title"
        standalone.seasonID = original.seasonID
        precondition(standalone.displayTitle == "Previously chosen title")
        let legacy = try JSONSerialization.data(withJSONObject: [
            "path": original.path, "title": base, "seasonID": original.seasonID!,
        ])
        let decoded = try JSONDecoder().decode(QueueMediaItem.self, from: legacy)
        precondition(decoded.displayTitleOverride == nil)
        let saved = UserDefaults.standard.object(forKey: HistoryStore.queueKey)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: HistoryStore.queueKey)
            } else {
                UserDefaults.standard.removeObject(forKey: HistoryStore.queueKey)
            }
        }
        HistoryStore.saveQueue([original])
        let coordinator = StreamCoordinator(libraryRecovery: nil)
        defer { coordinator.stop() }
        let undo = UndoManager()
        undo.groupsByEvent = false
        coordinator.setLibraryUndoManager(undo)
        undo.beginUndoGrouping()
        precondition(coordinator.setDisplayTitle("  My episode  ", for: original.id))
        undo.endUndoGrouping()
        precondition(coordinator.queueItems[0].displayTitle == "My episode")
        precondition(
            coordinator.queueItems[0].path == original.path && coordinator.queueItems[0].title == original.title)
        precondition(coordinator.queueItems[0].lastPosition == 42 && coordinator.queueItems[0].watched == true)
        precondition(HistoryStore.loadQueue()[0].displayTitle == "My episode")
        precondition(!coordinator.setDisplayTitle(" ", for: original.id))
        precondition(!coordinator.setDisplayTitle("Bad\nName", for: original.id))
        precondition(!coordinator.setDisplayTitle(String(repeating: "x", count: 161), for: original.id))
        precondition(!coordinator.setDisplayTitle("Name", for: "missing"))
        undo.undo()
        precondition(coordinator.queueItems == [original])
        undo.redo()
        precondition(coordinator.queueItems[0].displayTitle == "My episode")
        let relinked = HistoryStore.relocating(
            from: original.url, to: URL(fileURLWithPath: "/relocated/renamed.mkv"), recent: [],
            queue: coordinator.queueItems)
        precondition(relinked?.queue.first?.displayTitle == "My episode")
        undo.beginUndoGrouping()
        precondition(coordinator.setDisplayTitle(nil, for: original.id))
        undo.endUndoGrouping()
        precondition(coordinator.queueItems == [original])
        print(
            "Episode presentation: exact examples, ambiguous fallback, legacy decode, correction, persistence, Undo/Redo and relink: OK"
        )
    }
}
