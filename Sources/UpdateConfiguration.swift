import Foundation

struct UpdateConfiguration: Equatable, Sendable {
    let feedURL: URL?
    let publicKey: String?

    var isReady: Bool {
        feedURL?.scheme?.lowercased() == "https" && Self.isValidPublicKey(publicKey)
    }

    var feedHost: String? {
        guard isReady else { return nil }
        return feedURL?.host
    }

    static func load(from infoDictionary: [String: Any]?) -> Self {
        let feedValue = normalizedString(infoDictionary?["SUFeedURL"])
        let publicKey = normalizedString(infoDictionary?["SUPublicEDKey"])
        return Self(
            feedURL: feedValue.flatMap(URL.init(string:)),
            publicKey: publicKey
        )
    }

    private static func normalizedString(_ value: Any?) -> String? {
        guard let string = value as? String else { return nil }
        let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private static func isValidPublicKey(_ publicKey: String?) -> Bool {
        guard let publicKey, let decoded = Data(base64Encoded: publicKey) else { return false }
        return decoded.count == 32
    }
}
