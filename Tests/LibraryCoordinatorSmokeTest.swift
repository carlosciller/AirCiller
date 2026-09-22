import AppKit
import Foundation

/// Run only as an isolated check bundle with a fresh, UUID-suffixed preferences domain.
@main
struct LibraryCoordinatorSmokeTest {
    @MainActor
    static func main() throws {
        let prefix = "local.airciller.LibraryCoordinatorCheck."
        guard let domain = Bundle.main.bundleIdentifier, domain.hasPrefix(prefix),
            UUID(uuidString: String(domain.dropFirst(prefix.count))) != nil,
            CommandLine.arguments.contains("--skip-device-scan"),
            !CommandLine.arguments.contains("--autostart"),
            !CommandLine.arguments.contains("--airplay-test")
        else { throw Failure(message: "Requires a fresh isolated bundle and --skip-device-scan") }
        let defaults = UserDefaults.standard
        guard defaults.persistentDomain(forName: domain) == nil else {
            throw Failure(message: "Refusing to overwrite an existing preferences domain")
        }
        defer { defaults.removePersistentDomain(forName: domain) }
        let queue = ["a", "b", "c"].map {
            QueueMediaItem(path: "/synthetic-library/\($0).mkv", title: $0)
        }
        let recent = queue.enumerated().map { index, item in
            RecentMediaItem(
                path: item.path, title: item.title, lastOpened: Date(timeIntervalSince1970: 100),
                lastPosition: Double(index + 1) * 10, duration: 900)
        }
        HistoryStore.saveQueue(queue)
        HistoryStore.saveRecent(recent)
        let coordinator = StreamCoordinator()
        let manager = UndoManager()
        manager.groupsByEvent = false
        coordinator.setLibraryUndoManager(manager)
        // Synthetic playback flags prove library actions leave the session fields alone.
        coordinator.isStreaming = true
        coordinator.isPlaying = true
        coordinator.currentTime = 42
        coordinator.duration = 900
        coordinator.focusQueueItem(queue[1])

        action(manager) { coordinator.removeQueueItem(queue[1]) }
        try require(coordinator.queueItems.map(\.id) == [queue[0].id, queue[2].id], "production remove")
        try require(coordinator.focusedQueueItemID == queue[2].id, "production remove focus")
        manager.undo()
        try require(
            coordinator.queueItems == queue && coordinator.focusedQueueItemID == queue[1].id, "production undo remove")
        manager.redo()
        try require(coordinator.queueItems.count == 2, "production redo remove")
        manager.undo()

        action(manager) { _ = coordinator.moveFocusedQueueItem(by: -1) }
        try require(
            coordinator.queueItems.map(\.id) == [queue[1].id, queue[0].id, queue[2].id], "production keyboard move")
        manager.undo()
        try require(coordinator.queueItems == queue, "production keyboard move undo")
        action(manager) { coordinator.moveQueueItems(ids: [queue[2].id], before: queue[0].id) }
        try require(coordinator.queueItems.first == queue[2], "production drag move")
        manager.undo()
        try require(coordinator.queueItems == queue, "production drag move undo")
        action(manager) { coordinator.clearQueue() }
        try require(coordinator.queueItems.isEmpty && coordinator.focusedQueueItemID == nil, "production clear")
        manager.undo()
        try require(
            coordinator.queueItems == queue && coordinator.focusedQueueItemID == queue[1].id, "production clear undo")

        coordinator.focusedRecentItemID = recent[1].id
        action(manager) { coordinator.removeRecent(recent[1]) }
        try require(
            coordinator.recentItems.count == 2 && coordinator.focusedRecentItemID == recent[2].id,
            "production recent remove")
        manager.undo()
        try require(
            coordinator.recentItems == recent && coordinator.focusedRecentItemID == recent[1].id,
            "production recent undo")
        action(manager) { coordinator.clearRecent() }
        try require(
            coordinator.recentItems.isEmpty && coordinator.focusedRecentItemID == nil, "production recent clear")
        manager.undo()
        try require(
            coordinator.recentItems == recent && coordinator.focusedRecentItemID == recent[1].id,
            "production recent clear undo")
        try require(HistoryStore.loadQueue() == queue && HistoryStore.loadRecent() == recent, "production persistence")
        let playbackStatus = coordinator.status
        let playbackDetail = coordinator.detail
        coordinator.shortcutsEnqueue(queue[0].url)
        try require(coordinator.queueItems == queue, "shortcut adding an existing entry keeps playlist order")
        try require(
            coordinator.status == playbackStatus && coordinator.detail == playbackDetail,
            "shortcut adding during playback preserves the session message")
        let controller = ShortcutsController()
        controller.register(coordinator)
        do {
            try controller.openMovie(url: queue[0].url, removedOnCompletion: false)
            throw Failure(message: "shortcut replaced the active production coordinator")
        } catch ShortcutsFailure.busy {}
        try require(
            coordinator.selectedURL == nil && coordinator.isStreaming && coordinator.isPlaying
                && coordinator.currentTime == 42 && coordinator.duration == 900
                && !coordinator.airPlay.isScanning && !coordinator.airPlay.isSessionActive,
            "library actions preserve playback fields without starting a receiver session")

        action(manager) { coordinator.clearRecent() }
        manager.removeAllActions()
        // These synchronous calls exercise the real opening boundary. No actor yield
        // occurs before Stop cancels analysis, so no probe or receiver is started.
        for index in 0...HistoryStore.maximumRecentItems {
            if index == HistoryStore.maximumRecentItems {
                coordinator.focusedRecentItemID = coordinator.recentItems.last?.id
            }
            coordinator.loadVideo(
                URL(fileURLWithPath: "/synthetic-library/opened-\(index).mkv"),
                autoStart: false, startingAt: Double(index) * 10)
            coordinator.duration = 900
        }
        coordinator.stop()
        let boundedRecent = coordinator.recentItems
        try require(
            boundedRecent.count == HistoryStore.maximumRecentItems
                && boundedRecent.first?.title == "opened-30"
                && boundedRecent.last?.title == "opened-1",
            "31st opening trims the live history at the same boundary as persistence")
        try require(coordinator.focusedRecentItemID == nil, "trimmed row does not retain stale selection")
        try require(HistoryStore.loadRecent() == boundedRecent, "live and reloaded history are identical")

        let tail = boundedRecent[boundedRecent.count - 1]
        coordinator.loadVideo(tail.url, autoStart: false, startingAt: 211)
        coordinator.duration = 900
        coordinator.stop()
        try require(
            coordinator.recentItems.map(\.id) == boundedRecent.map(\.id)
                && coordinator.recentItems.last?.lastPosition == 211
                && coordinator.recentItems.last?.duration == 900,
            "reopening the oldest retained entry preserves order and its newest progress")

        let removedRecent = coordinator.recentItems[5]
        action(manager) { coordinator.removeRecent(removedRecent) }
        coordinator.loadVideo(
            URL(fileURLWithPath: "/synthetic-library/latest.mkv"), autoStart: false, startingAt: 123)
        coordinator.duration = 900
        coordinator.stop()
        let filledRecent = coordinator.recentItems
        manager.undo()
        try require(
            coordinator.recentItems == filledRecent && coordinator.recentItems.count == HistoryStore.maximumRecentItems
                && !coordinator.recentItems.contains { $0.id == removedRecent.id }
                && coordinator.recentItems.first?.lastPosition == 123
                && coordinator.recentItems.last?.lastPosition == 211,
            "Undo at a refilled limit retains current entries and their latest progress")
        try require(HistoryStore.loadRecent() == coordinator.recentItems, "bounded Undo persistence")
        try require(
            !coordinator.isAnalyzing && !coordinator.isPlaying && !coordinator.isStreaming
                && !coordinator.airPlay.isScanning && !coordinator.airPlay.isSessionActive,
            "bounded opening checks finish without analysis or a receiver session")
        coordinator.setLibraryUndoManager(nil)
        try require(!manager.canUndo && !manager.canRedo, "detaching window removes only library history")
        print("Production coordinator library Undo/Redo, selection, persistence and session-state preservation: OK")
    }

    @MainActor
    private static func action(_ manager: UndoManager, _ operation: () -> Void) {
        manager.beginUndoGrouping()
        operation()
        manager.endUndoGrouping()
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw Failure(message: message) }
    }

    private struct Failure: Error { let message: String }
}
