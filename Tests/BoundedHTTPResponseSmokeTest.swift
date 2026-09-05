import Foundation

@main
struct BoundedHTTPResponseSmokeTest {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        for path in ["known", "unknown"] {
            let request = URLRequest(url: URL(string: "https://fixture.invalid/\(path)")!)
            let (data, _) = try await BoundedHTTPResponse.data(for: request, using: session, maximumBytes: 4_096)
            guard data == Data(repeating: 65, count: 4_096) else { throw Failure.truncated }
            do {
                _ = try await BoundedHTTPResponse.data(for: request, using: session, maximumBytes: 4_095)
                throw Failure.exceededLimit
            } catch BoundedHTTPResponse.Failure.tooLarge {
                // Both advertised and actual byte counts must be bounded.
            }
        }
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            let request = URLRequest(url: URL(string: "https://fixture.invalid/unknown")!)
            _ = try await BoundedHTTPResponse.data(for: request, using: session, maximumBytes: 4_096)
        }
        do {
            try await cancelled.value
            throw Failure.ignoredCancellation
        } catch is CancellationError {}
        print("HTTP response limits apply with and without Content-Length; cancelled requests do not start: OK")
    }

    private enum Failure: Error { case truncated, exceededLimit, ignoredCancellation }
}

private final class FixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let headers = url.lastPathComponent == "known" ? ["Content-Length": "4096"] : [:]
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        for _ in 0..<4 { client?.urlProtocol(self, didLoad: Data(repeating: 65, count: 1_024)) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
