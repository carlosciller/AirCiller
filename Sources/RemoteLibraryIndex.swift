import CryptoKit
import Foundation

/// Identifiers remain stable across restart when supplied the same private
/// installation key. Only the Mac needs this key or the underlying local paths.
struct RemoteLibraryIndex {
    struct Item: Codable, Equatable, Sendable {
        let id: UUID
        let title: String
        let seasonID: UUID?
        let seasonTitle: String?
        let watched: Bool
        let position: Double
    }

    private let key: SymmetricKey

    init(key: Data) {
        precondition(key.count == 32)
        self.key = SymmetricKey(data: key)
    }

    func identifier(namespace: String, localID: String) -> UUID {
        let message = Data((namespace + "\u{0}" + localID).utf8)
        var bytes = Array(HMAC<SHA256>.authenticationCode(for: message, using: key).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
    }

    func search(_ query: String, queue: [QueueMediaItem], seasons: [SeasonFolder]) -> [Item] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.utf8.count <= 256 else { return [] }
        return queue.compactMap { item in
            let season = seasons.first(where: { $0.id == item.seasonID })
            guard
                item.title.localizedStandardContains(normalized)
                    || season?.title.localizedStandardContains(normalized) == true
            else { return nil }
            return Item(
                id: identifier(namespace: "media", localID: item.id), title: item.title,
                seasonID: season.map { identifier(namespace: "season", localID: $0.id) },
                seasonTitle: season?.title, watched: item.watched ?? false,
                position: item.lastPosition.flatMap { $0.isFinite ? max(0, $0) : nil } ?? 0)
        }
    }

    func resolve(_ id: UUID, queue: [QueueMediaItem]) -> QueueMediaItem? {
        let matches = queue.filter { identifier(namespace: "media", localID: $0.id) == id }
        // A collision or corrupted duplicate is not permission to pick one.
        return matches.count == 1 ? matches[0] : nil
    }
}
