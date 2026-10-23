import Foundation

@main
struct OpenSubtitlesRedirectSmokeTest {
    static func main() async throws {
        let api = OpenSubtitlesRedirectPolicy(mode: .api)
        let download = OpenSubtitlesRedirectPolicy(mode: .subtitle)
        let origin = URL(string: "https://api.opensubtitles.com/api/v1/login")!
        guard api.allowsRedirect(from: origin, to: URL(string: "https://API.opensubtitles.com:443/login")),
            !api.allowsRedirect(from: origin, to: URL(string: "https://other.opensubtitles.com/login")),
            download.allowsRedirect(from: origin, to: URL(string: "https://dl.opensubtitles.com/file"))
        else { throw Failure.policy }
        for destination in [
            "http://api.opensubtitles.com/login", "https://outside.invalid/login",
            "https://api.opensubtitles.com:8443/login", "https://user@api.opensubtitles.com/login",
            "https://api.opensubtitles.com.outside.invalid/login",
        ] {
            guard !api.allowsRedirect(from: origin, to: URL(string: destination)),
                !download.allowsRedirect(from: origin, to: URL(string: destination))
            else { throw Failure.policy }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let service = OpenSubtitlesService(
            credentialStore: OpenSubtitlesCredentialStore(backend: FixtureCredentials()), session: session)
        do {
            _ = try await service.testConnection()
            throw Failure.followedRedirect
        } catch OpenSubtitlesError.http(let status, _) where status == 307 {
            // The redirect response remains visible; no request reaches its target.
        }
        guard RedirectFixtureProtocol.requests.value == 1 else { throw Failure.followedRedirect }
        let downloads = OpenSubtitlesService(
            credentialStore: OpenSubtitlesCredentialStore(backend: FixtureCredentials(hasAccount: false)),
            session: session)
        let result = OpenSubtitlesSearchResult(
            subtitleID: "1", fileID: 1, fileName: "fixture.srt", language: "en", title: "Fixture", year: nil,
            release: "", downloadCount: 1, rating: 0, isTrusted: true, isHearingImpaired: false,
            isForced: false, isMachineTranslated: false, isAITranslated: false, isExactFileMatch: true)
        do {
            _ = try await downloads.download(result)
            throw Failure.followedRedirect
        } catch OpenSubtitlesError.http(let status, _) where status == 307 {}
        guard RedirectFixtureProtocol.requests.value == 3 else { throw Failure.followedRedirect }
        print("OpenSubtitles blocks off-origin API and off-service subtitle redirects before sending: OK")
    }

    private enum Failure: Error { case policy, followedRedirect }
}

private struct FixtureCredentials: OpenSubtitlesCredentialBackend {
    var hasAccount = true
    func credentials() -> OpenSubtitlesCredentials? {
        OpenSubtitlesCredentials(
            apiKey: "synthetic-key", username: hasAccount ? "synthetic-user" : "",
            password: hasAccount ? "synthetic-password" : "")
    }
    func storeCredentials(_ credentials: OpenSubtitlesCredentials) {}
    func removeCredentials() {}
}

private final class RequestCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class RedirectFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let requests = RequestCount()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.increment()
        guard let url = request.url else { return }
        if url.path.hasSuffix("/download") {
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(
                self,
                didLoad: Data(#"{"link":"https://dl.opensubtitles.com/fixture.srt","file_name":"fixture.srt"}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } else if ["api.opensubtitles.com", "dl.opensubtitles.com"].contains(url.host ?? "") {
            let destination = URL(string: "https://outside.invalid/collect")!
            let response = HTTPURLResponse(
                url: url, statusCode: 307, httpVersion: "HTTP/1.1",
                headerFields: ["Location": destination.absoluteString])!
            var redirected = request
            redirected.url = destination
            client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
        }
    }

    override func stopLoading() {}
}
