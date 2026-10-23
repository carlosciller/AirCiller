import Foundation

@main
struct RemoteLibraryIndexSmokeTest {
    static func main() throws {
        let key = Data(repeating: 7, count: 32)
        let index = RemoteLibraryIndex(key: key)
        let season = SeasonFolder(path: "/private/season", title: "Example Season", isExpanded: true)
        let a = QueueMediaItem(path: "/private/a.mkv", title: "Episode", seasonID: season.id)
        let b = QueueMediaItem(path: "/private/b.mkv", title: "Episode", seasonID: season.id)
        let found = index.search("episode", queue: [a, b], seasons: [season])
        precondition(found.count == 2 && found[0].id != found[1].id)
        precondition(index.search("example season", queue: [a, b], seasons: [season]).count == 2)
        precondition(index.search("private", queue: [a, b], seasons: [season]).isEmpty)
        precondition(index.search(" ", queue: [a], seasons: []).isEmpty)
        precondition(index.resolve(found[0].id, queue: [a, b]) == a)
        precondition(index.resolve(found[0].id, queue: [b]) == nil)
        precondition(index.resolve(found[0].id, queue: [a, a]) == nil)
        let restarted = RemoteLibraryIndex(key: key)
        precondition(restarted.search("episode", queue: [a, b], seasons: [season]) == found)
        let other = RemoteLibraryIndex(key: Data(repeating: 8, count: 32))
        precondition(other.resolve(found[0].id, queue: [a, b]) == nil)
        let json = String(decoding: try JSONEncoder().encode(found), as: UTF8.self)
        precondition(!json.contains("/private") && !json.contains(".mkv"))
        print("Remote library identifiers and ambiguous search: OK")
    }
}
