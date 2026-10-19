import AppKit
import Foundation

/// Run only as an isolated check bundle with a fresh, UUID-suffixed preferences domain.
@main
struct LibraryCoordinatorSmokeTest {
    @MainActor
    static func main() async throws {
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
        let imported = URL(fileURLWithPath: "/synthetic-library/season episode 01.mkv")
        coordinator.handleURLs([imported])
        try require(
            coordinator.queueItems.contains { $0.path == imported.path },
            "single opening enters Playlist before analysis")
        try require(HistoryStore.loadQueue() == coordinator.queueItems, "single opening persists before analysis")
        coordinator.stop()
        coordinator.isStreaming = true
        coordinator.isPlaying = true
        let sessionURL = coordinator.selectedURL
        let sessionStatus = coordinator.status
        let sessionDetail = coordinator.detail
        let nextImport = URL(fileURLWithPath: "/synthetic-library/season episode 02.mkv")
        coordinator.handleURLs([nextImport, imported])
        try require(
            coordinator.queueItems.filter { $0.path == imported.path }.count == 1, "import duplicate stays unique")
        try require(
            coordinator.queueItems.contains { $0.path == nextImport.path }, "import during playback enters Playlist")
        try require(
            coordinator.selectedURL == sessionURL && coordinator.isStreaming && coordinator.isPlaying
                && coordinator.status == sessionStatus && coordinator.detail == sessionDetail,
            "import preserves active session and its presentation")
        try require(HistoryStore.loadQueue() == coordinator.queueItems, "active-session import persists")
        let externalName = URL(fileURLWithPath: "/Volumes/External/Temporada - El niño & capítulo 01.mkv")
        coordinator.handleURLs([externalName, URL(fileURLWithPath: "/synthetic-library/notes.txt")])
        try require(
            coordinator.queueItems.contains { $0.path == externalName.path }
                && coordinator.libraryImportIssues.count == 1,
            "mixed admission retains an external-path filename and explains the rejected item")
        try require(
            coordinator.selectedURL == sessionURL && coordinator.isStreaming && coordinator.isPlaying,
            "mixed rejection does not interrupt playback")
        let restoredCoordinator = StreamCoordinator()
        try require(
            restoredCoordinator.queueItems == coordinator.queueItems,
            "admitted files survive a new coordinator before analysis succeeds")
        coordinator.isStreaming = false
        coordinator.isPlaying = false
        let legacy = Data("[{\"path\":\"/legacy.mkv\",\"title\":\"Legacy\"}]".utf8)
        let decoded = try JSONDecoder().decode([QueueMediaItem].self, from: legacy)
        try require(
            decoded.count == 1 && decoded[0].seasonID == nil && decoded[0].watched == nil,
            "legacy Playlist decodes without discarding entries")
        var episode = decoded[0]
        episode.seasonID = "/season"
        episode.lastPosition = 120
        episode.duration = 600
        episode.watched = true
        let encodedEpisode = try JSONEncoder().encode(episode)
        let decodedEpisode = try JSONDecoder().decode(QueueMediaItem.self, from: encodedEpisode)
        try require(
            decodedEpisode == episode,
            "episode state survives encoding")
        let season = SeasonFolder(path: "/season", title: "Season 1", isExpanded: false)
        HistoryStore.saveSeasons([season])
        try require(HistoryStore.loadSeasons() == [season], "season expansion persists")
        try await verifySeasonIntegration(coordinator, manager: manager)
        coordinator.setLibraryUndoManager(nil)
        try require(!manager.canUndo && !manager.canRedo, "detaching window removes only library history")
        print("Production coordinator library Undo/Redo, selection, persistence and session-state preservation: OK")
    }

    @MainActor
    private static func verifySeasonIntegration(_ coordinator: StreamCoordinator, manager: UndoManager) async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory
        let fixtureBase: URL
        if let volumePath = ProcessInfo.processInfo.environment["AIRCILLER_TEST_VOLUME_ROOT"] {
            fixtureBase = URL(fileURLWithPath: volumePath, isDirectory: true)
            let volumeInfo = try FileManager.default.attributesOfFileSystem(forPath: fixtureBase.path)
            let temporaryInfo = try FileManager.default.attributesOfFileSystem(forPath: temporaryRoot.path)
            try require(
                volumeInfo[.systemNumber] as? NSNumber != temporaryInfo[.systemNumber] as? NSNumber,
                "opt-in volume fixture must use a separate filesystem")
        } else {
            fixtureBase = temporaryRoot
        }
        let root = fixtureBase.appendingPathComponent("LibrarySeason-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let second = root.appendingPathComponent("Second season.mkv")
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let first = root.appendingPathComponent("First season")
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        for folder in [first, second] {
            for name in ["Episode 10.mkv", "Episode 2.mkv", "Episode 1.mkv"] {
                try Data("fixture".utf8).write(to: folder.appendingPathComponent(name))
            }
        }
        coordinator.isStreaming = true
        coordinator.isPlaying = true
        let playingURL = coordinator.selectedURL
        coordinator.handleURLs([first], analyzeFirst: false)
        coordinator.handleURLs([second], analyzeFirst: false)
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while coordinator.isImportingLibrary && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(!coordinator.isImportingLibrary, "folder import completes within its test bound")
        try require(
            !coordinator.queueItems.contains { $0.path == second.path },
            "folder with a movie extension is not admitted as a movie")
        try require(coordinator.importedFileCount == 6, "receipt counts newly added episodes")
        coordinator.handleURLs([first], analyzeFirst: false)
        let duplicateDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        while coordinator.isImportingLibrary && ContinuousClock.now < duplicateDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(!coordinator.isImportingLibrary, "duplicate import finishes")
        try require(coordinator.importedFileCount == 0, "reimport does not claim duplicate additions")
        let episodes = coordinator.queueItems.filter { $0.seasonID == first.path }
        try require(
            episodes.map(\.title) == ["Episode 1", "Episode 2", "Episode 10"], "folder episodes ordered numerically")
        try require(
            coordinator.queueItems.filter { $0.seasonID == second.path }.count == 3,
            "new import does not silently cancel an earlier folder")
        try require(
            coordinator.selectedURL == playingURL && coordinator.isStreaming && coordinator.isPlaying,
            "folder import preserves active playback")
        coordinator.setSeasonExpanded(first.path, expanded: false)
        try require(
            HistoryStore.loadSeasons().first { $0.id == first.path }?.isExpanded == false,
            "real coordinator persists expansion")
        action(manager) { coordinator.setWatched(episodes[0], watched: true) }
        try require(coordinator.queueItems.first { $0.id == episodes[0].id }?.watched == true, "manual watched saved")
        manager.undo()
        try require(coordinator.queueItems.first { $0.id == episodes[0].id }?.watched != true, "manual watched Undo")
        var progressQueue = coordinator.queueItems
        if let index = progressQueue.firstIndex(where: { $0.id == episodes[0].id }) {
            progressQueue[index].lastPosition = 42
            progressQueue[index].duration = 120
        }
        HistoryStore.saveQueue(progressQueue)
        let progressCoordinator = StreamCoordinator()
        let progressUndo = UndoManager()
        progressUndo.groupsByEvent = false
        progressCoordinator.setLibraryUndoManager(progressUndo)
        action(progressUndo) { progressCoordinator.setWatched(episodes[0], watched: true) }
        try require(progressUndo.undoActionName == L10n.text("Marcar como visto"), "watched action name")
        action(progressUndo) { progressCoordinator.setWatched(episodes[0], watched: false) }
        try require(progressUndo.undoActionName == L10n.text("Marcar como pendiente"), "unwatched action name")
        try require(
            progressCoordinator.queueItems.first { $0.id == episodes[0].id }?.lastPosition == 42,
            "marking pending preserves playback progress")
        progressUndo.undo()
        try require(progressUndo.redoActionName == L10n.text("Marcar como pendiente"), "unwatched Redo name")
        try require(
            progressCoordinator.queueItems.first { $0.id == episodes[0].id }?.lastPosition == 42,
            "watched Undo preserves playback progress")
        if let index = progressQueue.firstIndex(where: { $0.id == episodes[0].id }) {
            progressQueue[index].lastPosition = 120
            progressQueue[index].watched = false
        }
        HistoryStore.saveQueue(progressQueue)
        let completedCoordinator = StreamCoordinator()
        completedCoordinator.loadVideo(episodes[0].url, autoStart: false)
        let completedStart = completedCoordinator.currentTime
        completedCoordinator.stop()
        try require(completedStart == 0, "completed episode marked pending restarts at the beginning")
        HistoryStore.saveQueue(coordinator.queueItems)
        try verifyNativeSeasonDrag(coordinator, manager: manager)
        coordinator.focusQueueItem(episodes[0])
        try require(!coordinator.canMoveFocusedQueueItemUp, "first episode disables Move Up")
        try require(!coordinator.moveFocusedQueueItem(by: -1), "episode cannot move outside its season")
        coordinator.focusQueueItem(episodes[2])
        try require(!coordinator.canMoveFocusedQueueItemDown, "last episode disables Move Down")
        coordinator.focusQueueItem(episodes[1])
        action(manager) { _ = coordinator.moveFocusedQueueItem(by: -1) }
        try require(
            coordinator.queueItems.filter { $0.seasonID == first.path }.first?.id == episodes[1].id,
            "episode moves inside season")
        manager.undo()
        let beforeRemoval = coordinator.queueItems
        action(manager) { coordinator.removeSeason(first.path) }
        try require(
            !coordinator.queueItems.contains { $0.seasonID == first.path }, "group removal removes its episodes")
        manager.undo()
        try require(coordinator.queueItems == beforeRemoval, "group Undo restores episode metadata and order")
        try require(FileManager.default.fileExists(atPath: episodes[0].path), "library removal preserves originals")
        coordinator.isStreaming = false
        coordinator.isPlaying = false
        coordinator.loadVideo(episodes[0].url, autoStart: false)
        coordinator.duration = 120
        coordinator.currentTime = 120
        coordinator.airPlay.onPlaybackEnded?()
        try require(coordinator.selectedURL == episodes[1].url, "natural completion selects next grouped episode")
        try require(
            coordinator.queueItems.first { $0.id == episodes[0].id }?.watched == true,
            "natural completion persists watched state")
        coordinator.stop()
        // No actor yield occurs between loading, injected end and Stop: no probe,
        // preparation or receiver session is started by the completion fixture.
        try require(HistoryStore.loadQueue() == coordinator.queueItems, "season and progress state persisted")
        let cancelledFolder = root.appendingPathComponent("Cancelled season")
        let queuedFolder = root.appendingPathComponent("Queued season")
        for folder in [cancelledFolder, queuedFolder] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: folder.appendingPathComponent("Episode 1.mkv"))
        }
        let beforeCancellation = coordinator.queueItems
        coordinator.handleURLs([cancelledFolder], analyzeFirst: false)
        coordinator.handleURLs([queuedFolder], analyzeFirst: false)
        coordinator.cancelLibraryImport()
        try await Task.sleep(for: .milliseconds(50))
        try require(
            !coordinator.isImportingLibrary && coordinator.queueItems == beforeCancellation,
            "cancelling queued imports prevents delayed admission and retains existing items")
        coordinator.handleURLs([queuedFolder], analyzeFirst: false)
        let retryDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        while coordinator.isImportingLibrary && ContinuousClock.now < retryDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(
            !coordinator.isImportingLibrary
                && coordinator.queueItems.filter { $0.seasonID == queuedFolder.path }.count == 1
                && !coordinator.queueItems.contains { $0.seasonID == cancelledFolder.path },
            "new import succeeds after cancellation without reviving the abandoned queue")
        let vanishedFolder = root.appendingPathComponent("Vanished season")
        try FileManager.default.createDirectory(at: vanishedFolder, withIntermediateDirectories: true)
        coordinator.handleURLs([vanishedFolder], analyzeFirst: false)
        try FileManager.default.removeItem(at: vanishedFolder)
        let vanishedDeadline = ContinuousClock.now.advanced(by: .seconds(10))
        while coordinator.isImportingLibrary && ContinuousClock.now < vanishedDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try require(
            !coordinator.isImportingLibrary && !coordinator.libraryImportIssues.isEmpty,
            "folder disappearing before its scan is reported, not silently skipped")
    }

    @MainActor
    private static func verifyNativeSeasonDrag(_ coordinator: StreamCoordinator, manager: UndoManager) throws {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 2000),
            styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let outline = NSOutlineView(frame: window.contentView!.bounds)
        outline.addTableColumn(NSTableColumn(identifier: .init("Library")))
        window.contentView = outline
        let adapter = NativeSeasonOutline.Coordinator(coordinator)
        outline.dataSource = adapter
        outline.delegate = adapter
        adapter.refresh(outline)
        let rootCount = adapter.outlineView(outline, numberOfChildrenOfItem: nil)
        let group = (0..<rootCount).map { adapter.outlineView(outline, child: $0, ofItem: nil) }
            .first { adapter.outlineView(outline, isItemExpandable: $0) }
        guard let group else { throw Failure(message: "native season root missing") }
        outline.expandItem(group)
        let source = adapter.outlineView(outline, child: 1, ofItem: group)
        let target = adapter.outlineView(outline, child: 0, ofItem: group)
        guard let cell = adapter.outlineView(outline, viewFor: nil, item: source) as? NSTableCellView else {
            throw Failure(message: "native cell missing")
        }
        try require(!cell.draggingImageComponents.isEmpty, "native cell provides a drag image")
        let pasteboard = NSPasteboard(name: .init("LibrarySeasonDrag-\(UUID())"))
        defer { pasteboard.releaseGlobally() }
        guard let writer = adapter.outlineView(outline, pasteboardWriterForItem: source),
            pasteboard.writeObjects([writer])
        else { throw Failure(message: "native drag writer failed") }
        let targetFrame = outline.rect(ofRow: outline.row(forItem: target))
        let location = outline.convert(
            NSPoint(x: 100, y: targetFrame.minY + targetFrame.height * 0.25), to: nil)
        let dragging = SeasonDraggingFixture(
            source: outline, pasteboard: pasteboard, window: window, location: location)
        try require(
            adapter.outlineView(outline, validateDrop: dragging, proposedItem: target, proposedChildIndex: -1) == .move,
            "native drop on the upper half of an episode accepts insertion")
        let original = coordinator.queueItems
        var accepted = false
        action(manager) {
            accepted = adapter.outlineView(outline, acceptDrop: dragging, item: target, childIndex: -1)
        }
        try require(accepted && coordinator.queueItems != original, "native episode drop changes order")
        manager.undo()
        try require(coordinator.queueItems == original, "native episode drop Undo restores order")
        guard let sourceID = pasteboard.string(forType: NativeSeasonOutline.Coordinator.dragType),
            let sourceSeason = original.first(where: { $0.id == sourceID })?.seasonID
        else { throw Failure(message: "native episode identity missing") }
        adapter.refresh(outline)
        outline.expandItem(group)
        let last = adapter.outlineView(outline, child: 2, ofItem: group)
        let lastFrame = outline.rect(ofRow: outline.row(forItem: last))
        let lowerLocation = outline.convert(
            NSPoint(x: 100, y: lastFrame.minY + lastFrame.height * 0.75), to: nil)
        let lowerDrop = SeasonDraggingFixture(
            source: outline, pasteboard: pasteboard, window: window, location: lowerLocation)
        try require(
            adapter.outlineView(outline, validateDrop: lowerDrop, proposedItem: last, proposedChildIndex: -1) == .move,
            "native drop on lower half of final episode accepts insertion")
        action(manager) {
            accepted = adapter.outlineView(outline, acceptDrop: lowerDrop, item: last, childIndex: -1)
        }
        try require(
            accepted && coordinator.queueItems.filter { $0.seasonID == sourceSeason }.last?.id == sourceID,
            "native final-row drop moves episode to the end of its season")
        manager.undo()
        try require(coordinator.queueItems == original, "native final-row drop Undo restores order")
        adapter.refresh(outline)
        let groupIndex = (0..<rootCount).first {
            adapter.outlineView(outline, child: $0, ofItem: nil) as AnyObject === group as AnyObject
        }
        guard let groupIndex else { throw Failure(message: "native group index missing") }
        try require(
            adapter.outlineView(
                outline, validateDrop: dragging, proposedItem: nil, proposedChildIndex: groupIndex + 1) == .move,
            "root boundary after a season accepts its last episode insertion")
        if let otherGroup = (0..<rootCount).map({ adapter.outlineView(outline, child: $0, ofItem: nil) })
            .first(where: {
                adapter.outlineView(outline, isItemExpandable: $0) && $0 as AnyObject !== group as AnyObject
            })
        {
            try require(
                adapter.outlineView(
                    outline, validateDrop: dragging, proposedItem: otherGroup, proposedChildIndex: 0
                ).isEmpty,
                "native episode drop cannot reparent into another season")
        } else {
            throw Failure(message: "second native season missing")
        }
        pasteboard.clearContents()
        guard let groupWriter = adapter.outlineView(outline, pasteboardWriterForItem: group),
            pasteboard.writeObjects([groupWriter])
        else { throw Failure(message: "native season writer failed") }
        try require(
            adapter.outlineView(outline, validateDrop: dragging, proposedItem: nil, proposedChildIndex: 0) == .move,
            "native season drop accepts root insertion")
        action(manager) {
            accepted = adapter.outlineView(outline, acceptDrop: dragging, item: nil, childIndex: 0)
        }
        try require(
            accepted && coordinator.queueItems.first?.seasonID == sourceSeason,
            "native group drop moves its episodes together")
        manager.undo()
        try require(coordinator.queueItems == original, "native group drop Undo restores order")
        adapter.refresh(outline)
        outline.expandItem(group)
        guard let firstMenu = adapter.menu(outline.row(forItem: target)) else {
            throw Failure(message: "native episode menu missing")
        }
        firstMenu.update()
        try require(
            firstMenu.items.first { $0.title == L10n.text("Mover arriba") }?.isEnabled == false,
            "native first-episode context menu disables Move Up")
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

@MainActor
private final class SeasonDraggingFixture: NSObject, NSDraggingInfo {
    let draggingDestinationWindow: NSWindow?
    let draggingSourceOperationMask: NSDragOperation = .move
    let draggingLocation: NSPoint
    let draggedImageLocation: NSPoint = .zero
    nonisolated var draggedImage: NSImage? { nil }
    let draggingPasteboard: NSPasteboard
    let draggingSource: Any?
    let draggingSequenceNumber = 1
    var draggingFormation: NSDraggingFormation = .none
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    let springLoadingHighlight: NSSpringLoadingHighlight = .none

    init(source: NSOutlineView, pasteboard: NSPasteboard, window: NSWindow, location: NSPoint) {
        draggingSource = source
        draggingPasteboard = pasteboard
        draggingDestinationWindow = window
        draggingLocation = location
    }

    func slideDraggedImage(to screenPoint: NSPoint) {}
    nonisolated override func namesOfPromisedFilesDropped(atDestination dropDestination: URL) -> [String]? { nil }
    func resetSpringLoading() {}
    func enumerateDraggingItems(
        options enumOpts: NSDraggingItemEnumerationOptions, for view: NSView?, classes classArray: [AnyClass],
        searchOptions: [NSPasteboard.ReadingOptionKey: Any],
        using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void
    ) {}
}
