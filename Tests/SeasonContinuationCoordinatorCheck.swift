import Foundation

enum SeasonContinuationCoordinatorCheck {
    @MainActor static func run() throws {
        let defaults = UserDefaults.standard
        let keys = [HistoryStore.queueKey, HistoryStore.recentKey, HistoryStore.seasonsKey]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, saved) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("SeasonContinue-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appendingPathComponent("Episode 10.mkv")
        let secondURL = directory.appendingPathComponent("Episode 2.mkv")
        try Data().write(to: firstURL)
        try Data().write(to: secondURL)
        let season = SeasonFolder(path: directory.path, title: "Season One", isExpanded: false)
        let first = QueueMediaItem(
            path: firstURL.path, title: "Episode 10", seasonID: season.id, lastPosition: 7, duration: 100, watched: true
        )
        let second = QueueMediaItem(
            path: secondURL.path, title: "Episode 2", seasonID: season.id, lastPosition: 42, duration: 100)
        HistoryStore.saveQueue([first, second])
        HistoryStore.saveSeasons([season])
        HistoryStore.saveRecent([])
        let coordinator = StreamCoordinator(libraryRecovery: nil)
        defer { coordinator.stop() }
        coordinator.focusQueueSeason(season.id)
        precondition(
            coordinator.selectedURL == nil && !coordinator.isAnalyzing, "Focusing a season must not load media")
        precondition(coordinator.continuation(forSeason: season.id)?.item.id == second.id)
        precondition(coordinator.continuation(forSeason: season.id)?.position == 42)
        precondition(!coordinator.continueSeason("missing-season"))
        coordinator.isPreparing = true
        precondition(!coordinator.canContinueSeason && !coordinator.continueSeason(season.id))
        precondition(coordinator.selectedURL == nil)
        coordinator.isPreparing = false
        coordinator.showConversionAlert = true
        precondition(
            !coordinator.continueSeason(season.id) && coordinator.showConversionAlert,
            "Continuation must not replace a pending audio decision")
        coordinator.showConversionAlert = false
        precondition(coordinator.continueSeason(season.id))
        precondition(coordinator.selectedURL == secondURL && coordinator.currentTime == 42 && coordinator.isAnalyzing)
        precondition(
            coordinator.queueItems == [first, second], "Explicit continuation must preserve order and watched state")
        precondition(!coordinator.continueSeason(season.id), "Do not duplicate an in-flight load")
        coordinator.stop()
        coordinator.isStreaming = true
        coordinator.isPlaying = true
        let sessionID = coordinator.remoteControlSessionID
        precondition(coordinator.continueSeason(season.id))
        precondition(
            coordinator.remoteControlSessionID == sessionID && !coordinator.isAnalyzing,
            "Continuing the active playing episode must not restart it")
        coordinator.stop()
        coordinator.setWatched(second, watched: true)
        precondition(coordinator.continuation(forSeason: season.id) == nil && !coordinator.continueSeason(season.id))
        coordinator.setWatched(first, watched: false)
        try FileManager.default.removeItem(at: firstURL)
        precondition(coordinator.continuation(forSeason: season.id)?.item.id == first.id)
        // The explicit action opens the existing native Locate/Cancel alert.
        // Exercise that interaction in native QA, not a headless modal loop.
        precondition(!HistoryStore.isAvailable(firstURL))
        precondition(coordinator.selectedURL == secondURL)
        print(
            "Continue Season coordinator: selection, busy guard, exact load/resume, active session, completion and missing-file target: OK"
        )
    }
}
