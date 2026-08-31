import Foundation
import Security

protocol AirPlayCredentialBackend: Sendable {
    func credential(for deviceID: String) -> String?
    func storeCredential(_ credential: String, for deviceID: String) throws
    func removeCredential(for deviceID: String) throws
}

struct KeychainAirPlayCredentialBackend: AirPlayCredentialBackend {
    private let service = "local.carlosciller.AirCiller.AirPlay"

    func credential(for deviceID: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func storeCredential(_ credential: String, for deviceID: String) throws {
        let data = Data(credential.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID,
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

    func removeCredential(for deviceID: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: deviceID,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}

/// Serializes every credential mutation so an old removal cannot race a new pairing result.
actor AirPlayCredentialStore {
    private let backend: any AirPlayCredentialBackend

    init(backend: any AirPlayCredentialBackend = KeychainAirPlayCredentialBackend()) {
        self.backend = backend
    }

    func credential(for deviceID: String) -> String? {
        backend.credential(for: deviceID)
    }

    func storeCredential(_ credential: String, for deviceID: String) throws {
        try backend.storeCredential(credential, for: deviceID)
    }

    func removeCredential(for deviceID: String) throws {
        try backend.removeCredential(for: deviceID)
    }
}
