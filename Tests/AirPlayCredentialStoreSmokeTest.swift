import Foundation

@main
struct AirPlayCredentialStoreSmokeTest {
    static func main() async throws {
        let backend = InMemoryCredentialBackend()
        let store = AirPlayCredentialStore(backend: backend)

        try await store.storeCredential("old", for: "living-room")
        try await store.removeCredential(for: "living-room")
        try await store.storeCredential("fresh", for: "living-room")
        guard await store.credential(for: "living-room") == "fresh" else {
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
        guard await store.credential(for: "shared") == "final",
            !backend.detectedOverlap
        else {
            throw NSError(domain: "AirPlayCredentialStoreSmokeTest.Serialization", code: 2)
        }

        print("AirPlay credential reads, removals, and pairing writes are serialized: OK")
    }
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
