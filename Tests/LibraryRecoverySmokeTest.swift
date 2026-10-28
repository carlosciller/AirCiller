import Foundation

@main
struct LibraryRecoverySmokeTest {
    struct Failure: Error { let message: String }
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw Failure(message: message) }
    }

    @MainActor
    static func main() throws {
        let suite = "AirCiller.RecoveryTest.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let recovery = LibraryRecovery(defaults: defaults, archive: .init(directory: root))
        try require(recovery.inspect().isEmpty, "First launch without library is not an error")
        let item = QueueMediaItem(
            path: "/synthetic/Episode.mkv", title: "Episode", seasonID: "/synthetic",
            lastPosition: 123, duration: 900, watched: true)
        HistoryStore.saveQueue([item], defaults: defaults)
        HistoryStore.saveRecent([], defaults: defaults)
        HistoryStore.saveSeasons(
            [SeasonFolder(path: "/synthetic", title: "Season", isExpanded: false)], defaults: defaults)
        let validQueue = defaults.data(forKey: HistoryStore.queueKey)!
        let validSeasons = defaults.data(forKey: HistoryStore.seasonsKey)!
        try require(recovery.inspect().isEmpty, "Current format checkpoints without changing library")
        try require(defaults.data(forKey: HistoryStore.queueKey) == validQueue, "Startup keeps exact current bytes")

        let damaged = Data("[{\"path\":\"/synthetic/Episode.mkv\"}, broken".utf8)
        defaults.set(damaged, forKey: HistoryStore.queueKey)
        let issues = recovery.inspect()
        try require(issues.count == 1 && issues[0].problem == .malformedData, "Partial corruption is scoped")
        try require(defaults.data(forKey: HistoryStore.queueKey) == damaged, "Inspection never resets damage")
        try require(defaults.data(forKey: HistoryStore.seasonsKey) == validSeasons, "Unchanged collection retained")
        try require(HistoryStore.loadQueue(defaults: defaults).isEmpty, "Invalid input is not partially guessed")
        HistoryStore.saveQueue([], defaults: defaults)
        try require(
            defaults.data(forKey: HistoryStore.queueKey) == damaged, "Later saves cannot replace unreadable data")
        try require(recovery.inspect().count == 1, "Repeated launch retains the same issue")
        // Simulate interruption after the archive is marked resolved but before
        // preferences change. Startup must reopen the same incident, not reset.
        try recovery.archive.markResolved(damaged, collection: .queue)
        try require(recovery.inspect().count == 1, "Interrupted restoration remains visible")
        try require(
            try recovery.archive.read(.queue, slot: .incident)?.resolvedAt == nil,
            "Interrupted restore reopens the incident")
        try require(defaults.data(forKey: HistoryStore.queueKey) == damaged, "Interrupted restore preserves original")
        try recovery.restore(issues[0], useCheckpoint: true)
        try require(HistoryStore.loadQueue(defaults: defaults) == [item], "Explicit restore keeps order and progress")
        try require(
            try recovery.archive.read(.queue, slot: .incident)?.payload == damaged,
            "Restore retains the failed bytes")
        // Restoring the same prompt again must not overwrite a now-valid list.
        do {
            try recovery.restore(issues[0], useCheckpoint: true)
            throw Failure(message: "Stale recovery accepted")
        } catch LibraryRecovery.Failure.changedSinceInspection {}

        defaults.set(Data("second different failure".utf8), forKey: HistoryStore.queueKey)
        let repeated = recovery.inspect()
        try require(repeated.first?.problem == .malformedData, "New failure after recovery remains recoverable")
        try require(
            try recovery.archive.read(.queue, slot: .previousIncident)?.payload == damaged,
            "First resolved failure is retained separately")
        defaults.set(Data("third failure before resolution".utf8), forKey: HistoryStore.queueKey)
        let unresolved = recovery.inspect()
        try require(
            unresolved.first?.problem == .archive(.occupiedIncident), "Unresolved incident cannot be overwritten")
        do {
            try recovery.restore(unresolved[0], useCheckpoint: false)
            throw Failure(message: "Unpreserved second failure replaced")
        } catch LibraryRecoveryArchive.Failure.occupiedIncident {}
        try require(
            defaults.data(forKey: HistoryStore.queueKey) == Data("third failure before resolution".utf8),
            "Second failure remains live when preservation is blocked")

        // Total corruption and incompatible data are distinct, independently
        // recoverable collections. No valid checkpoint means no restore offer.
        defaults.set(Data("not json".utf8), forKey: HistoryStore.recentKey)
        defaults.set(Data("{\"version\":99}".utf8), forKey: HistoryStore.seasonsKey)
        let total = recovery.inspect()
        try require(total.count == 3, "Total corruption reports every collection")
        let seasonsIssue = total.first { $0.collection == .seasons }!
        try require(
            seasonsIssue.problem == .unrecognizedFormat, "Newer or unknown format is not labeled malformed JSON")
        try recovery.restore(seasonsIssue, useCheckpoint: true)
        try require(defaults.data(forKey: HistoryStore.seasonsKey) == validSeasons, "Season expansion restored")
        let recentIssue = total.first { $0.collection == .recent }!
        try recovery.restore(recentIssue, useCheckpoint: false)
        try require(
            defaults.data(forKey: HistoryStore.recentKey) == Data("[]".utf8),
            "Explicit empty recovery only affects selected collection")

        defaults.set(validQueue, forKey: HistoryStore.queueKey)
        var smallArchive = LibraryRecoveryArchive(directory: root.appendingPathComponent("bounded"))
        smallArchive.maximumRecordBytes = 32
        let bounded = LibraryRecovery(defaults: defaults, archive: smallArchive)
        try require(bounded.inspect().contains { $0.problem == .archive(.tooLarge) }, "Archive limit is visible")
        try require(
            defaults.data(forKey: HistoryStore.queueKey) == validQueue, "Archive failure leaves valid data intact")
        print(
            "Library recovery: startup, corruption, repeated failures, explicit restore, stale prompts and bounds: OK")
    }
}
