import Foundation

@main
struct SeasonContinuationSmokeTest {
    static func main() {
        let first = QueueMediaItem(
            path: "/fixture/02.mkv", title: "Episode 2", seasonID: "s", lastPosition: 42, duration: 100)
        let second = QueueMediaItem(
            path: "/fixture/01.mkv", title: "Episode 1", seasonID: "s", lastPosition: 17, duration: 100)
        let other = QueueMediaItem(path: "/fixture/other.mkv", title: "Other", seasonID: "other")
        func target(_ items: [QueueMediaItem], recent: [RecentMediaItem] = []) -> SeasonContinuation? {
            SeasonContinuation.target(seasonID: "s", items: items, recent: recent)
        }
        precondition(target([other, first, second])?.item.id == first.id, "Manual order must win over filename order")
        precondition(target([first, second])?.position == 42)
        precondition(target([second, first])?.item.id == second.id, "Reordering immediately changes the target")
        var watched = first
        watched.watched = true
        precondition(target([watched, second])?.item.id == second.id)
        var lastWatched = second
        lastWatched.watched = true
        precondition(target([watched, lastWatched]) == nil, "Do not silently replay a completed season")
        precondition(target([]) == nil && target([other]) == nil)
        var pending = first
        pending.lastPosition = 100
        precondition(target([pending])?.position == 0, "Completed episode marked pending starts at the beginning")
        pending.lastPosition = nil
        let recent = RecentMediaItem(
            path: first.path, title: first.title, lastOpened: .distantPast, lastPosition: 23, duration: 100)
        precondition(target([pending], recent: [recent])?.position == 23, "Legacy recent progress remains usable")
        pending.lastPosition = 0
        precondition(target([pending], recent: [recent])?.position == 0, "Explicit queue zero overrides Recents")
        pending.lastPosition = -.infinity
        precondition(target([pending])?.position == 0)
        pending.lastPosition = -7
        precondition(target([pending])?.position == 0)
        precondition(SeasonContinuation.resumePosition(queued: nil, recent: recent) == 23)
        precondition(SeasonContinuation.resumePosition(queued: nil, recent: nil) == 0)
        // No file-system filtering: a missing pending episode is not silently skipped.
        precondition(target([first, second])?.item.path == "/fixture/02.mkv")
        print("Season continuation: manual order, watched state, resume, legacy progress and completed seasons: OK")
    }
}
