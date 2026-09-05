import Darwin
import Foundation

@main
struct HTTPServerSmokeTest {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCillerHTTPTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let segment = Data((0..<1_048_576).map { UInt8($0 % 251) })
        try segment.write(to: directory.appendingPathComponent("segment.m4s"))
        try segment.write(to: directory.appendingPathComponent("segment.ts"))
        let hugeFileURL = directory.appendingPathComponent("large.mp4")
        let hugeFileSize = 5 * 1024 * 1024 * 1024
        FileManager.default.createFile(atPath: hugeFileURL.path, contents: nil)
        let hugeFile = try FileHandle(forWritingTo: hugeFileURL)
        try hugeFile.truncate(atOffset: UInt64(hugeFileSize))
        try hugeFile.close()
        try "#EXTM3U\n#EXT-X-ENDLIST\n".write(
            to: directory.appendingPathComponent("video.m3u8"),
            atomically: true,
            encoding: .utf8
        )

        let telemetryRecorder = TelemetryRecorder()
        let server = LocalHTTPServer(
            rootDirectory: directory,
            allowsLoopbackAddress: true,
            telemetryHandler: { telemetry in
                telemetryRecorder.record(telemetry)
            }
        )
        let baseURL = try await server.start()
        defer { server.stop() }
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }

        mark("private path")
        var unprotectedComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        unprotectedComponents.path = "/segment.m4s"
        let (_, unprotectedResponse) = try await session.data(from: unprotectedComponents.url!)
        guard (unprotectedResponse as? HTTPURLResponse)?.statusCode == 404 else {
            throw NSError(domain: "HTTPServerSmokeTest.PrivatePath", code: 10)
        }

        mark("HEAD")
        var head = URLRequest(url: baseURL.appendingPathComponent("segment.m4s"))
        head.httpMethod = "HEAD"
        let (headData, headResponse) = try await session.data(for: head)
        guard let headHTTP = headResponse as? HTTPURLResponse,
            headHTTP.statusCode == 200,
            headData.isEmpty,
            headHTTP.value(forHTTPHeaderField: "Content-Length") == "1048576"
        else {
            throw NSError(domain: "HTTPServerSmokeTest.HEAD", code: 1)
        }

        mark("range")
        var range = URLRequest(url: baseURL.appendingPathComponent("segment.m4s"))
        range.setValue("bytes=100-199", forHTTPHeaderField: "Range")
        let (rangeData, rangeResponse) = try await session.data(for: range)
        guard let rangeHTTP = rangeResponse as? HTTPURLResponse,
            rangeHTTP.statusCode == 206,
            rangeData == segment.subdata(in: 100..<200),
            rangeHTTP.value(forHTTPHeaderField: "Content-Range") == "bytes 100-199/1048576",
            rangeHTTP.value(forHTTPHeaderField: "Connection")?.lowercased() == "keep-alive",
            rangeHTTP.value(forHTTPHeaderField: "Cache-Control")?.contains("immutable") == true
        else {
            throw NSError(domain: "HTTPServerSmokeTest.Range", code: 2)
        }

        mark("persistent keep-alive")
        try verifyPersistentRanges(baseURL: baseURL, expected: segment)

        for specification in ["bytes=abc-5", "bytes=999999999999999999999999-5"] {
            var malformed = range
            malformed.setValue(specification, forHTTPHeaderField: "Range")
            let (_, response) = try await session.data(for: malformed)
            guard (response as? HTTPURLResponse)?.statusCode == 416 else {
                throw NSError(domain: "HTTPServerSmokeTest.MalformedRange", code: 30)
            }
        }
        var suffix = range
        suffix.setValue("bytes=-5", forHTTPHeaderField: "Range")
        let (suffixData, suffixResponse) = try await session.data(for: suffix)
        guard (suffixResponse as? HTTPURLResponse)?.statusCode == 206,
            suffixData == Data(segment.suffix(5))
        else { throw NSError(domain: "HTTPServerSmokeTest.SuffixRange", code: 31) }

        mark("invalid range")
        var invalidRange = URLRequest(url: baseURL.appendingPathComponent("segment.m4s"))
        invalidRange.setValue("bytes=2000000-2000010", forHTTPHeaderField: "Range")
        do {
            let (_, response) = try await session.data(for: invalidRange)
            guard let http = response as? HTTPURLResponse,
                http.statusCode == 416,
                http.value(forHTTPHeaderField: "Content-Range") == "bytes */1048576"
            else {
                throw NSError(domain: "HTTPServerSmokeTest.InvalidRange", code: 4)
            }
        } catch let error as NSError where error.domain == NSURLErrorDomain {
            throw NSError(domain: "HTTPServerSmokeTest.InvalidRangeTransport", code: error.code)
        }

        mark("complete file")
        let (completeSegment, completeResponse) = try await session.data(
            from: baseURL.appendingPathComponent("segment.m4s")
        )
        guard (completeResponse as? HTTPURLResponse)?.statusCode == 200,
            completeSegment == segment
        else {
            throw NSError(domain: "HTTPServerSmokeTest.Complete", code: 5)
        }

        mark("range larger than 4 GB")
        let largeSession = URLSession(configuration: .ephemeral)
        var largeRange = URLRequest(url: baseURL.appendingPathComponent("large.mp4"))
        largeRange.setValue("bytes=0-\(hugeFileSize - 1)", forHTTPHeaderField: "Range")
        let (largeBytes, largeResponse) = try await largeSession.bytes(for: largeRange)
        guard let largeHTTP = largeResponse as? HTTPURLResponse,
            largeHTTP.statusCode == 206,
            largeHTTP.value(forHTTPHeaderField: "Content-Range") == "bytes 0-\(hugeFileSize - 1)/\(hugeFileSize)"
        else {
            throw NSError(domain: "HTTPServerSmokeTest.LargeRangeHeader", code: 7)
        }
        var streamedPrefix = 0
        for try await byte in largeBytes {
            guard byte == 0 else {
                throw NSError(domain: "HTTPServerSmokeTest.LargeRangeContent", code: 8)
            }
            streamedPrefix += 1
            if streamedPrefix == 65_536 { break }
        }
        largeSession.invalidateAndCancel()
        guard streamedPrefix == 65_536 else {
            throw NSError(domain: "HTTPServerSmokeTest.LargeRangeLength", code: 9)
        }

        mark("repeated abandoned large ranges")
        try await verifyAbandonedLargeRanges(baseURL: baseURL, fileSize: hugeFileSize)

        mark("transport stream")
        let (transportStream, transportResponse) = try await session.data(
            from: baseURL.appendingPathComponent("segment.ts")
        )
        guard let transportHTTP = transportResponse as? HTTPURLResponse,
            transportHTTP.statusCode == 200,
            transportHTTP.mimeType == "video/mp2t",
            transportStream == segment
        else {
            throw NSError(domain: "HTTPServerSmokeTest.TransportStream", code: 6)
        }

        mark("playlist")
        var playlistRequest = URLRequest(url: baseURL.appendingPathComponent("video.m3u8"))
        playlistRequest.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
        let (playlist, playlistResponse) = try await session.data(for: playlistRequest)
        guard (playlistResponse as? HTTPURLResponse)?.statusCode == 200,
            (playlistResponse as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Encoding") == nil,
            String(data: playlist, encoding: .utf8)?.contains("#EXT-X-ENDLIST") == true
        else {
            throw NSError(domain: "HTTPServerSmokeTest.Playlist", code: 3)
        }

        let telemetry = telemetryRecorder.snapshot
        print(
            "telemetry bytes=\(telemetry.totalBytesSent) completed=\(telemetry.completedTransfers) "
                + "expected=\(telemetry.expectedDisconnects) errors=\(telemetry.unexpectedErrors) "
                + "capacity=\(telemetry.observedCapacityBitsPerSecond ?? -1)"
        )
        guard telemetry.totalBytesSent >= Int64(segment.count * 3),
            telemetry.completedTransfers >= 3,
            telemetry.unexpectedErrors == 0
        else {
            throw NSError(
                domain: "HTTPServerSmokeTest.Telemetry",
                code: 11,
                userInfo: [NSLocalizedDescriptionKey: String(describing: telemetry)]
            )
        }

        mark("telemetry filter")
        let excludedRecorder = TelemetryRecorder()
        let filteredServer = LocalHTTPServer(
            rootDirectory: directory,
            telemetryClientAddress: "203.0.113.99",
            allowsLoopbackAddress: true,
            telemetryHandler: { telemetry in
                excludedRecorder.record(telemetry)
            }
        )
        let filteredBaseURL = try await filteredServer.start()
        let (filteredData, _) = try await session.data(
            from: filteredBaseURL.appendingPathComponent("segment.m4s")
        )
        filteredServer.stop()
        guard filteredData == segment,
            excludedRecorder.snapshot.hasConfirmedMediaRequest,
            excludedRecorder.snapshot.totalBytesSent == 0,
            excludedRecorder.snapshot.completedTransfers == 0
        else {
            throw NSError(domain: "HTTPServerSmokeTest.TelemetryFilter", code: 12)
        }

        guard let localAddress = baseURL.host else {
            throw NSError(domain: "HTTPServerSmokeTest.TelemetryAddress", code: 17)
        }
        let includedRecorder = TelemetryRecorder()
        let measuredServer = LocalHTTPServer(
            rootDirectory: directory,
            telemetryClientAddress: localAddress,
            allowsLoopbackAddress: true,
            telemetryHandler: { telemetry in
                includedRecorder.record(telemetry)
            }
        )
        let measuredBaseURL = try await measuredServer.start()
        let (measuredData, _) = try await session.data(
            from: measuredBaseURL.appendingPathComponent("segment.m4s")
        )
        measuredServer.stop()
        guard measuredData == segment,
            includedRecorder.snapshot.hasConfirmedMediaRequest,
            includedRecorder.snapshot.totalBytesSent == Int64(segment.count),
            includedRecorder.snapshot.completedTransfers == 1
        else {
            throw NSError(domain: "HTTPServerSmokeTest.TelemetryInclude", code: 18)
        }

        print(
            "Private HTTP, Range, >4 GB, abandoned ranges, keep-alive, cache, filtered telemetry, MIME, and HLS: OK"
        )
    }

    private static func mark(_ message: String) {
        FileHandle.standardError.write(Data(("[HTTP test] \(message)\n").utf8))
    }

    private static func verifyPersistentRanges(baseURL: URL, expected: Data) throws {
        guard let host = baseURL.host,
            let port = baseURL.port
        else {
            throw NSError(domain: "HTTPServerSmokeTest.KeepAliveURL", code: 13)
        }
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw POSIXError(.ENOTSOCK)
        }
        defer { Darwin.close(descriptor) }

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            throw NSError(domain: "HTTPServerSmokeTest.KeepAliveAddress", code: 14)
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECONNREFUSED) }

        let path = baseURL.appendingPathComponent("segment.m4s").path
        let first = try exchange(
            descriptor: descriptor,
            request:
                "GET \(path) HTTP/1.1\r\nHost: \(host):\(port)\r\nRange: bytes=0-99\r\nConnection: keep-alive\r\n\r\n"
        )
        guard first.header.contains("HTTP/1.1 206"),
            first.header.lowercased().contains("connection: keep-alive"),
            first.body == expected.subdata(in: 0..<100)
        else {
            throw NSError(domain: "HTTPServerSmokeTest.KeepAliveFirst", code: 15)
        }

        let second = try exchange(
            descriptor: descriptor,
            request:
                "GET \(path) HTTP/1.1\r\nHost: \(host):\(port)\r\nRange: bytes=100-199\r\nConnection: close\r\n\r\n",
            shutdownWriteAfterSend: true
        )
        guard second.header.contains("HTTP/1.1 206"),
            second.header.lowercased().contains("connection: close"),
            second.body == expected.subdata(in: 100..<200)
        else {
            throw NSError(domain: "HTTPServerSmokeTest.KeepAliveSecond", code: 16)
        }
    }

    private static func verifyAbandonedLargeRanges(baseURL: URL, fileSize: Int) async throws {
        guard let host = baseURL.host,
            let port = baseURL.port
        else {
            throw NSError(domain: "HTTPServerSmokeTest.AbandonedRangeURL", code: 19)
        }

        var originalLimit = rlimit()
        guard getrlimit(RLIMIT_NOFILE, &originalLimit) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var testLimit = originalLimit
        testLimit.rlim_cur = min(originalLimit.rlim_cur, 128)
        guard setrlimit(RLIMIT_NOFILE, &testLimit) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer {
            var restoredLimit = originalLimit
            _ = setrlimit(RLIMIT_NOFILE, &restoredLimit)
        }

        try await Task.sleep(for: .milliseconds(250))
        let baselineDescriptorCount = try openDescriptorCount()
        let path = baseURL.appendingPathComponent("large.mp4").path

        for index in 0..<160 {
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else {
                throw NSError(
                    domain: "HTTPServerSmokeTest.AbandonedRangeSocket",
                    code: 20,
                    userInfo: [NSLocalizedDescriptionKey: "socket failed after \(index) abandoned ranges"]
                )
            }

            do {
                var timeout = timeval(tv_sec: 2, tv_usec: 0)
                _ = withUnsafePointer(to: &timeout) {
                    setsockopt(
                        descriptor,
                        SOL_SOCKET,
                        SO_RCVTIMEO,
                        $0,
                        socklen_t(MemoryLayout<timeval>.size)
                    )
                }

                var address = sockaddr_in()
                address.sin_family = sa_family_t(AF_INET)
                address.sin_port = in_port_t(port).bigEndian
                guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
                    throw NSError(domain: "HTTPServerSmokeTest.AbandonedRangeAddress", code: 21)
                }
                let connected = withUnsafePointer(to: &address) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(
                            descriptor,
                            $0,
                            socklen_t(MemoryLayout<sockaddr_in>.size)
                        )
                    }
                }
                guard connected == 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECONNREFUSED)
                }

                let start = (index * 8_388_608) % (fileSize - 16_777_216)
                let request = Data(
                    "GET \(path) HTTP/1.1\r\nHost: \(host):\(port)\r\nRange: bytes=\(start)-\(fileSize - 1)\r\nConnection: keep-alive\r\n\r\n"
                        .utf8
                )
                try sendAll(request, through: descriptor)

                var prefix = [UInt8](repeating: 0, count: 16_384)
                let received = Darwin.recv(descriptor, &prefix, prefix.count, 0)
                guard received > 0,
                    String(decoding: prefix.prefix(received), as: UTF8.self).contains("HTTP/1.1 206")
                else {
                    throw NSError(domain: "HTTPServerSmokeTest.AbandonedRangeResponse", code: 22)
                }

                var reset = linger(l_onoff: 1, l_linger: 0)
                _ = withUnsafePointer(to: &reset) {
                    setsockopt(
                        descriptor,
                        SOL_SOCKET,
                        SO_LINGER,
                        $0,
                        socklen_t(MemoryLayout<linger>.size)
                    )
                }
            } catch {
                Darwin.close(descriptor)
                throw error
            }
            Darwin.close(descriptor)

            if index.isMultiple(of: 20) {
                try await Task.sleep(for: .milliseconds(25))
            }
        }

        try await Task.sleep(for: .seconds(1))
        let finalDescriptorCount = try openDescriptorCount()
        guard finalDescriptorCount <= baselineDescriptorCount + 12 else {
            throw NSError(
                domain: "HTTPServerSmokeTest.AbandonedRangeLeak",
                code: 23,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Open descriptors grew from \(baselineDescriptorCount) to \(finalDescriptorCount)"
                ]
            )
        }

        let healthSession = URLSession(configuration: .ephemeral)
        defer { healthSession.invalidateAndCancel() }
        var healthRequest = URLRequest(url: baseURL.appendingPathComponent("segment.m4s"))
        healthRequest.setValue("bytes=0-99", forHTTPHeaderField: "Range")
        let (healthData, healthResponse) = try await healthSession.data(for: healthRequest)
        guard (healthResponse as? HTTPURLResponse)?.statusCode == 206,
            healthData.count == 100
        else {
            throw NSError(domain: "HTTPServerSmokeTest.AbandonedRangeHealth", code: 24)
        }
    }

    private static func openDescriptorCount() throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count
    }

    private static func sendAll(_ data: Data, through descriptor: Int32) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var sent = 0
            while sent < bytes.count {
                let result = Darwin.send(
                    descriptor,
                    baseAddress.advanced(by: sent),
                    bytes.count - sent,
                    0
                )
                guard result > 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPIPE)
                }
                sent += result
            }
        }
    }

    private static func exchange(
        descriptor: Int32,
        request: String,
        shutdownWriteAfterSend: Bool = false
    ) throws -> (header: String, body: Data) {
        let requestData = Data(request.utf8)
        try requestData.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var sent = 0
            while sent < bytes.count {
                let result = Darwin.send(descriptor, baseAddress.advanced(by: sent), bytes.count - sent, 0)
                guard result > 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EPIPE)
                }
                sent += result
            }
        }
        if shutdownWriteAfterSend, Darwin.shutdown(descriptor, SHUT_WR) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var response = Data()
        let separator = Data("\r\n\r\n".utf8)
        var headerRange: Range<Data.Index>?
        var expectedLength: Int?
        while true {
            if let headerRange,
                let expectedLength,
                response.count - headerRange.upperBound >= expectedLength
            {
                let headerData = response[..<headerRange.lowerBound]
                let bodyStart = headerRange.upperBound
                let bodyEnd = bodyStart + expectedLength
                return (
                    String(decoding: headerData, as: UTF8.self),
                    Data(response[bodyStart..<bodyEnd])
                )
            }
            var buffer = [UInt8](repeating: 0, count: 4096)
            let received = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            guard received > 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECONNRESET)
            }
            response.append(contentsOf: buffer.prefix(received))
            if headerRange == nil, let found = response.range(of: separator) {
                headerRange = found
                let header = String(decoding: response[..<found.lowerBound], as: UTF8.self)
                expectedLength =
                    header
                    .components(separatedBy: "\r\n")
                    .first(where: { $0.lowercased().hasPrefix("content-length:") })
                    .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) }
            }
        }
    }
}

private final class TelemetryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var value = HTTPServerTelemetry.empty

    func record(_ telemetry: HTTPServerTelemetry) {
        lock.lock()
        value = telemetry
        lock.unlock()
    }

    var snapshot: HTTPServerTelemetry {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
