import Foundation
import Security

struct OpenSubtitlesCredentials: Codable, Equatable, Sendable {
    let apiKey: String
    let username: String
    let password: String

    var isConfigured: Bool {
        !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasAccount: Bool {
        !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
    }

    var normalized: OpenSubtitlesCredentials {
        OpenSubtitlesCredentials(
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password
        )
    }
}

protocol OpenSubtitlesCredentialBackend: Sendable {
    func credentials() throws -> OpenSubtitlesCredentials?
    func storeCredentials(_ credentials: OpenSubtitlesCredentials) throws
    func removeCredentials() throws
}

struct KeychainOpenSubtitlesCredentialBackend: OpenSubtitlesCredentialBackend {
    private let service = "local.carlosciller.AirCiller.OpenSubtitles"
    private let account = "credentials"

    func credentials() throws -> OpenSubtitlesCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        return try JSONDecoder().decode(OpenSubtitlesCredentials.self, from: data)
    }

    func storeCredentials(_ credentials: OpenSubtitlesCredentials) throws {
        let data = try JSONEncoder().encode(credentials.normalized)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw NSError(domain: NSOSStatusErrorDomain, code: Int(addStatus))
            }
        } else if status != errSecSuccess {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    func removeCredentials() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

actor OpenSubtitlesCredentialStore {
    private let backend: any OpenSubtitlesCredentialBackend

    init(backend: any OpenSubtitlesCredentialBackend = KeychainOpenSubtitlesCredentialBackend()) {
        self.backend = backend
    }

    func credentials() throws -> OpenSubtitlesCredentials? {
        try backend.credentials()
    }

    func storeCredentials(_ credentials: OpenSubtitlesCredentials) throws {
        try backend.storeCredentials(credentials.normalized)
    }

    func removeCredentials() throws {
        try backend.removeCredentials()
    }
}
