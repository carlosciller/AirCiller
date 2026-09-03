import Foundation

@main
struct OpenSubtitlesCredentialStoreSmokeTest {
    static func main() async throws {
        let backend = InMemoryOpenSubtitlesCredentialBackend()
        let store = OpenSubtitlesCredentialStore(backend: backend)
        let credentials = OpenSubtitlesCredentials(
            apiKey: "  app-key  ",
            username: " carlos ",
            password: "secret"
        )

        try await store.storeCredentials(credentials)
        guard
            await (try store.credentials())
                == OpenSubtitlesCredentials(
                    apiKey: "app-key",
                    username: "carlos",
                    password: "secret"
                )
        else {
            throw NSError(domain: "OpenSubtitlesCredentialStoreSmokeTest.Store", code: 1)
        }

        try await store.removeCredentials()
        guard await (try store.credentials()) == nil else {
            throw NSError(domain: "OpenSubtitlesCredentialStoreSmokeTest.Remove", code: 2)
        }

        print("OpenSubtitles credentials are normalized and stored as one serialized value: OK")
    }
}

private final class InMemoryOpenSubtitlesCredentialBackend:
    OpenSubtitlesCredentialBackend, @unchecked Sendable
{
    private let lock = NSLock()
    private var value: OpenSubtitlesCredentials?

    func credentials() throws -> OpenSubtitlesCredentials? {
        lock.withLock { value }
    }

    func storeCredentials(_ credentials: OpenSubtitlesCredentials) throws {
        lock.withLock { value = credentials }
    }

    func removeCredentials() throws {
        lock.withLock { value = nil }
    }
}
