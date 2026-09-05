import Foundation

enum BoundedHTTPResponse {
    enum Failure: Error { case tooLarge }

    /// Enforce the limit while reading, including chunked responses with no
    /// Content-Length. Checking after data(for:) has already allocated is too late.
    static func data(
        for request: URLRequest,
        using session: URLSession,
        maximumBytes: Int
    ) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard maximumBytes >= 0, response.expectedContentLength <= Int64(maximumBytes) else {
            throw Failure.tooLarge
        }
        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(Int(response.expectedContentLength))
        }
        for try await byte in bytes {
            guard data.count < maximumBytes else { throw Failure.tooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        return (data, response)
    }
}
