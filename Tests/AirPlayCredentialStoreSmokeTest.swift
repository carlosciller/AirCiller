import Foundation

@main
struct AirPlayCredentialStoreSmokeTest {
    static func main() async throws {
        let backend = InMemoryCredentialBackend()
        let store = AirPlayCredentialStore(backend: backend)

        try await store.storeCredential("old", for: "living-room")
        try await store.removeCredential(for: "living-room")
        try await store.storeCredential("fresh", for: "living-room")
        guard try await store.credential(for: "living-room") == "fresh" else {
            throw NSError(domain: "AirPlayCredentialStoreSmokeTest.Order", code: 1)
        }

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<30 {
                group.addTask {
                    try? await store.storeCredential("value-\(index)", for: "shared")
                }
            }
        }
        try await store.storeCredential("final", for: "shared")
        guard try await store.credential(for: "shared") == "final",
            !backend.detectedOverlap
        else {
            throw NSError(domain: "AirPlayCredentialStoreSmokeTest.Serialization", code: 2)
        }

        let unavailable = AirPlayCredentialStore(backend: UnavailableCredentialBackend())
        do {
            _ = try await unavailable.credential(for: "living-room")
            throw NSError(domain: "AirPlayCredentialStoreSmokeTest.ErrorHiddenAsMissing", code: 3)
        } catch let error as NSError where error.domain == "KeychainUnavailable" {
            // Denied or locked Keychain access must not trigger fresh pairing.
        }
        guard try await store.credential(for: "missing") == nil else {
            throw NSError(domain: "AirPlayCredentialStoreSmokeTest.Missing", code: 4)
        }
        print("AirPlay credential access is serialized; unavailable and missing credentials remain distinct: OK")
    }
}

private struct UnavailableCredentialBackend: AirPlayCredentialBackend {
    func credential(for deviceID: String) throws -> String? {
        throw NSError(domain: "KeychainUnavailable", code: -25308)
    }
    func storeCredential(_ credential: String, for deviceID: String) throws {}
    func removeCredential(for deviceID: String) throws {}
}

private final class InMemoryCredentialBackend: AirPlayCredentialBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]
    private var activeOperations = 0
    private(set) var detectedOverlap = false

    func credential(for deviceID: String) -> String? {
        operation { values[deviceID] }
    }

    func storeCredential(_ credential: String, for deviceID: String) throws {
        operation { values[deviceID] = credential }
    }

    func removeCredential(for deviceID: String) throws {
        _ = operation { values.removeValue(forKey: deviceID) }
    }

    private func operation<T>(_ body: () -> T) -> T {
        lock.lock()
        activeOperations += 1
        if activeOperations > 1 { detectedOverlap = true }
        lock.unlock()
        Thread.sleep(forTimeInterval: 0.001)
        let result = body()
        lock.lock()
        activeOperations -= 1
        lock.unlock()
        return result
    }
}
