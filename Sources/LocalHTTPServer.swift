import Darwin
import Foundation
import Network
import OSLog

final class LocalHTTPServer: @unchecked Sendable {
    private let rootDirectory: URL
    private let pathToken: String
    private let telemetryClientAddress: String?
    private let allowsLoopbackAddress: Bool
    private let telemetryHandler: (@Sendable (HTTPServerTelemetry) -> Void)?
    private let queue = DispatchQueue(label: "local.airciller.http", qos: .userInitiated)
    private let logger = Logger(subsystem: "local.carlosciller.AirCiller", category: "HTTP")
    private var listener: NWListener?
    private var activeConnections: [ObjectIdentifier: NWConnection] = [:]
    private var requestGenerations: [ObjectIdentifier: UInt64] = [:]
    private var transfers: [ObjectIdentifier: TransferState] = [:]
    private var recentCapacitySamples: [Double] = []
    private var totalBytesSent: Int64 = 0
    private var completedTransfers = 0
    private var expectedDisconnects = 0
    private var unexpectedErrors = 0
    private var lastActivity: Date?
    private var lastTelemetryEmission = Date.distantPast

    private struct TransferState {
        let startedAt: Date
        let expectedBytes: Int
        let fileName: String
        let isTelemetryClient: Bool
        let keepAlive: Bool
        let bufferedRequestData: Data
        var bytesSent: Int64 = 0
        var lastChunkAt: Date
    }

    init(
        rootDirectory: URL,
        telemetryClientAddress: String? = nil,
        allowsLoopbackAddress: Bool = false,
        telemetryHandler: (@Sendable (HTTPServerTelemetry) -> Void)? = nil
    ) {
        self.rootDirectory = rootDirectory.standardizedFileURL.resolvingSymlinksInPath()
        self.pathToken = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        self.telemetryClientAddress = telemetryClientAddress
        self.allowsLoopbackAddress = allowsLoopbackAddress
        self.telemetryHandler = telemetryHandler
    }

    func start() async throws -> URL {
        let listener = try NWListener(using: .tcp, on: NWEndpoint.Port.any)
        self.listener = listener

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let gate = ContinuationGate()

                listener.newConnectionHandler = { [weak self] connection in
                    self?.handle(connection)
                }

                listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        guard let port = listener.port?.rawValue,
                            let address = Self.localIPv4Address(allowLoopback: self.allowsLoopbackAddress),
                            let url = URL(string: "http://\(address):\(port)/\(self.pathToken)/")
                        else {
                            gate.resume(continuation, with: .failure(ServerError.noLocalAddress))
                            return
                        }
                        gate.resume(continuation, with: .success(url))
                    case .failed(let error):
                        gate.resume(continuation, with: .failure(error))
                    case .cancelled:
                        gate.resume(continuation, with: .failure(ServerError.cancelled))
                    default:
                        break
                    }
                }

                listener.start(queue: queue)
            }
        } onCancel: {
            listener.cancel()
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        queue.async { [weak self] in
            guard let self else { return }
            for connection in self.activeConnections.values {
                connection.cancel()
            }
            self.activeConnections.removeAll()
            self.requestGenerations.removeAll()
            self.transfers.removeAll()
        }
    }

    private func handle(_ connection: NWConnection) {
        let identifier = ObjectIdentifier(connection)
        activeConnections[identifier] = connection
        requestGenerations[identifier] = 0
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.activeConnections.removeValue(forKey: identifier)
                self?.requestGenerations.removeValue(forKey: identifier)
                self?.transfers.removeValue(forKey: identifier)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        let separator = Data("\r\n\r\n".utf8)
        if let headerRange = accumulated.range(of: separator) {
            let request = Data(accumulated[..<headerRange.upperBound])
            let bufferedRequestData = Data(accumulated[headerRange.upperBound...])
            respond(
                to: request,
                bufferedRequestData: bufferedRequestData,
                on: connection
            )
            return
        }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) {
            [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var request = accumulated
            if let data {
                request.append(data)
            }

            if request.count > 131_072 {
                self.send(status: 400, reason: "Bad Request", body: Data(), type: "text/plain", on: connection)
            } else if request.range(of: separator) != nil {
                // A peer may half-close its write side in the same callback that
                // delivers the complete request. Parse that request before
                // treating `isComplete` as a malformed/truncated message.
                self.receiveRequest(on: connection, accumulated: request)
            } else if isComplete || error != nil, request.isEmpty {
                connection.cancel()
                self.activeConnections.removeValue(forKey: ObjectIdentifier(connection))
            } else if isComplete || error != nil {
                self.send(status: 400, reason: "Bad Request", body: Data(), type: "text/plain", on: connection)
            } else {
                self.receiveRequest(on: connection, accumulated: request)
            }
        }
    }

    private func respond(
        to requestData: Data,
        bufferedRequestData: Data,
        on connection: NWConnection
    ) {
        guard let request = String(data: requestData, encoding: .utf8) else {
            send(status: 400, reason: "Bad Request", body: Data(), type: "text/plain", on: connection)
            return
        }

        let lines = request.components(separatedBy: "\r\n")
        guard let first = lines.first else {
            send(status: 400, reason: "Bad Request", body: Data(), type: "text/plain", on: connection)
            return
        }

        let requestParts = first.split(separator: " ")
        guard requestParts.count >= 2 else {
            send(status: 400, reason: "Bad Request", body: Data(), type: "text/plain", on: connection)
            return
        }

        let method = String(requestParts[0])
        guard method == "GET" || method == "HEAD" else {
            send(status: 405, reason: "Method Not Allowed", body: Data(), type: "text/plain", on: connection)
            return
        }

        let version = requestParts.count >= 3 ? String(requestParts[2]).uppercased() : "HTTP/1.0"
        let connectionHeader = lines.first(where: { $0.lowercased().hasPrefix("connection:") })?
            .split(separator: ":", maxSplits: 1)
            .last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let keepAlive =
            version == "HTTP/1.1"
            ? connectionHeader != "close"
            : connectionHeader == "keep-alive"
        requestGenerations[ObjectIdentifier(connection), default: 0] &+= 1

        let rawPath = String(requestParts[1]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
        let decodedPath = rawPath.removingPercentEncoding ?? rawPath
        let protectedPath = decodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let tokenPrefix = pathToken + "/"

        guard protectedPath.hasPrefix(tokenPrefix) else {
            send(status: 404, reason: "Not Found", body: Data(), type: "text/plain", on: connection)
            return
        }
        let relativePath = String(protectedPath.dropFirst(tokenPrefix.count))
        guard !relativePath.isEmpty, !relativePath.contains("..") else {
            send(status: 404, reason: "Not Found", body: Data(), type: "text/plain", on: connection)
            return
        }

        let fileURL =
            rootDirectory
            .appendingPathComponent(relativePath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        guard fileURL.path.hasPrefix(rootDirectory.path + "/"),
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true,
            let fileSize = values.fileSize
        else {
            send(status: 404, reason: "Not Found", body: Data(), type: "text/plain", on: connection)
            return
        }

        let type = mimeType(for: fileURL.pathExtension)
        let rangeHeader = lines.first(where: { $0.lowercased().hasPrefix("range:") })
        let client = String(describing: connection.endpoint)
        logger.info(
            "\(method, privacy: .public) /\(relativePath, privacy: .private) client=\(client, privacy: .private) range=\(rangeHeader ?? "-", privacy: .public)"
        )
        if let rangeHeader {
            guard let range = byteRange(from: rangeHeader, total: fileSize) else {
                send(
                    status: 416,
                    reason: "Range Not Satisfiable",
                    body: Data(),
                    type: "text/plain",
                    extraHeaders: ["Content-Range: bytes */\(fileSize)"],
                    keepAlive: keepAlive,
                    bufferedRequestData: bufferedRequestData,
                    on: connection
                )
                return
            }
            let headers = ["Content-Range: bytes \(range.lowerBound)-\(range.upperBound - 1)/\(fileSize)"]
            if method == "HEAD" {
                send(
                    status: 206,
                    reason: "Partial Content",
                    body: Data(),
                    type: type,
                    contentLength: range.count,
                    extraHeaders: headers,
                    keepAlive: keepAlive,
                    bufferedRequestData: bufferedRequestData,
                    on: connection
                )
            } else {
                sendFile(
                    status: 206,
                    reason: "Partial Content",
                    fileURL: fileURL,
                    range: range,
                    type: type,
                    extraHeaders: headers,
                    keepAlive: keepAlive,
                    bufferedRequestData: bufferedRequestData,
                    on: connection
                )
            }
        } else {
            if method == "HEAD" {
                send(
                    status: 200,
                    reason: "OK",
                    body: Data(),
                    type: type,
                    contentLength: fileSize,
                    keepAlive: keepAlive,
                    bufferedRequestData: bufferedRequestData,
                    on: connection
                )
            } else {
                // Apple's reference HLS CDN leaves playlists uncompressed even
                // when tvOS advertises gzip. Keeping the local response plain
                // avoids a parser rejection before EXT-X-MAP is requested.
                sendFile(
                    status: 200,
                    reason: "OK",
                    fileURL: fileURL,
                    range: 0..<fileSize,
                    type: type,
                    keepAlive: keepAlive,
                    bufferedRequestData: bufferedRequestData,
                    on: connection
                )
            }
        }
    }

    private func sendFile(
        status: Int,
        reason: String,
        fileURL: URL,
        range: Range<Int>,
        type: String,
        extraHeaders: [String] = [],
        keepAlive: Bool,
        bufferedRequestData: Data,
        on connection: NWConnection
    ) {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            logger.error(
                "HTTP \(status, privacy: .public) no pudo abrir \(fileURL.lastPathComponent, privacy: .private)")
            send(status: 500, reason: "Read Error", body: Data(), type: "text/plain", on: connection)
            return
        }
        do {
            try handle.seek(toOffset: UInt64(range.lowerBound))
        } catch {
            try? handle.close()
            send(status: 500, reason: "Read Error", body: Data(), type: "text/plain", on: connection)
            return
        }

        let header = responseHeader(
            status: status,
            reason: reason,
            type: type,
            contentLength: range.count,
            extraHeaders: extraHeaders,
            keepAlive: keepAlive
        )
        beginTransfer(
            on: connection,
            expectedBytes: range.count,
            fileName: fileURL.lastPathComponent,
            keepAlive: keepAlive,
            bufferedRequestData: bufferedRequestData
        )
        connection.send(
            content: header,
            contentContext: .defaultMessage,
            isComplete: false,
            completion: .contentProcessed { [weak self] error in
                guard let self else {
                    try? handle.close()
                    connection.cancel()
                    return
                }
                if let error {
                    try? handle.close()
                    self.failTransfer(status: status, error: error, on: connection)
                    return
                }
                self.sendNextFileChunk(
                    handle: handle,
                    remaining: range.count,
                    status: status,
                    on: connection
                )
            }
        )
    }

    private func sendNextFileChunk(
        handle: FileHandle,
        remaining: Int,
        status: Int,
        on connection: NWConnection
    ) {
        guard remaining > 0 else {
            try? handle.close()
            finishTransfer(on: connection)
            return
        }
        let requestedCount = min(1_048_576, remaining)
        let chunk: Data
        do {
            guard let read = try handle.read(upToCount: requestedCount), !read.isEmpty else {
                throw ServerError.unexpectedEndOfFile
            }
            chunk = read
        } catch {
            try? handle.close()
            failTransfer(status: status, error: error, on: connection)
            return
        }

        let nextRemaining = remaining - chunk.count
        let isFinalChunk = nextRemaining == 0
        let identifier = ObjectIdentifier(connection)
        let shouldClose = isFinalChunk && transfers[identifier]?.keepAlive != true
        connection.send(
            content: chunk,
            contentContext: .defaultMessage,
            isComplete: shouldClose,
            completion: .contentProcessed { [weak self] error in
                guard let self else {
                    try? handle.close()
                    connection.cancel()
                    return
                }
                if let error {
                    try? handle.close()
                    self.failTransfer(status: status, error: error, on: connection)
                } else if isFinalChunk {
                    self.recordTransferredBytes(chunk.count, on: connection)
                    try? handle.close()
                    self.finishTransfer(on: connection)
                } else {
                    self.recordTransferredBytes(chunk.count, on: connection)
                    self.sendNextFileChunk(
                        handle: handle,
                        remaining: nextRemaining,
                        status: status,
                        on: connection
                    )
                }
            }
        )
    }

    private func failTransfer(status: Int, error: Error, on connection: NWConnection) {
        let expected = Self.isExpectedClientDisconnect(error)
        finishTelemetry(for: connection, completed: false, expectedDisconnect: expected)
        if expected {
            logger.debug(
                "HTTP \(status, privacy: .public) cancelado por el reproductor al cambiar de rango"
            )
        } else {
            logger.error(
                "HTTP \(status, privacy: .public) interrumpido durante el envío progresivo: \(String(describing: error), privacy: .public)"
            )
        }
        activeConnections.removeValue(forKey: ObjectIdentifier(connection))
        connection.cancel()
    }

    private static func isExpectedClientDisconnect(_ error: Error) -> Bool {
        if let networkError = error as? NWError,
            case .posix(let code) = networkError
        {
            return code == .EPIPE || code == .ECONNRESET || code == .ECANCELED || code == .ENOTCONN
                || code == .ECONNABORTED
        }
        let cocoaError = error as NSError
        return cocoaError.domain == NSPOSIXErrorDomain
            && [Int(EPIPE), Int(ECONNRESET), Int(ECANCELED), Int(ENOTCONN), Int(ECONNABORTED)]
                .contains(cocoaError.code)
    }

    private func finishTransfer(on connection: NWConnection) {
        let transfer = finishTelemetry(for: connection, completed: true, expectedDisconnect: false)
        guard let transfer else {
            close(connection, after: 0.25)
            return
        }
        if transfer.keepAlive {
            continueReceiving(
                on: connection,
                bufferedRequestData: transfer.bufferedRequestData
            )
            return
        }
        close(connection, after: 0.25)
    }

    private func close(_ connection: NWConnection, after delay: TimeInterval) {
        let identifier = ObjectIdentifier(connection)
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard self?.activeConnections.removeValue(forKey: identifier) != nil else { return }
            self?.requestGenerations.removeValue(forKey: identifier)
            connection.cancel()
        }
    }

    private func continueReceiving(on connection: NWConnection, bufferedRequestData: Data) {
        let identifier = ObjectIdentifier(connection)
        let completedGeneration = requestGenerations[identifier] ?? 0
        receiveRequest(on: connection, accumulated: bufferedRequestData)
        queue.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self,
                self.requestGenerations[identifier] == completedGeneration,
                self.transfers[identifier] == nil,
                self.activeConnections.removeValue(forKey: identifier) != nil
            else { return }
            self.requestGenerations.removeValue(forKey: identifier)
            connection.cancel()
        }
    }

    private func beginTransfer(
        on connection: NWConnection,
        expectedBytes: Int,
        fileName: String,
        keepAlive: Bool,
        bufferedRequestData: Data
    ) {
        let identifier = ObjectIdentifier(connection)
        let isTelemetryClient = shouldMeasure(connection)
        transfers[identifier] = TransferState(
            startedAt: Date(),
            expectedBytes: expectedBytes,
            fileName: fileName,
            isTelemetryClient: isTelemetryClient,
            keepAlive: keepAlive,
            bufferedRequestData: bufferedRequestData,
            lastChunkAt: Date()
        )
        if isTelemetryClient {
            lastActivity = Date()
            emitTelemetry(force: true)
        }
    }

    private func recordTransferredBytes(_ count: Int, on connection: NWConnection) {
        guard count > 0 else { return }
        let identifier = ObjectIdentifier(connection)
        guard var transfer = transfers[identifier] else { return }
        let now = Date()
        let chunkElapsed = now.timeIntervalSince(transfer.lastChunkAt)
        transfer.bytesSent += Int64(count)
        transfer.lastChunkAt = now
        transfers[identifier] = transfer
        guard transfer.isTelemetryClient else { return }
        totalBytesSent += Int64(count)
        if count >= 524_288, chunkElapsed >= 0.01, chunkElapsed <= 8 {
            recentCapacitySamples.append(Double(count) * 8 / chunkElapsed)
            if recentCapacitySamples.count > 30 {
                recentCapacitySamples.removeFirst(recentCapacitySamples.count - 30)
            }
        }
        lastActivity = now
        emitTelemetry(force: false)
    }

    @discardableResult
    private func finishTelemetry(
        for connection: NWConnection,
        completed: Bool,
        expectedDisconnect: Bool
    ) -> TransferState? {
        let identifier = ObjectIdentifier(connection)
        let transfer = transfers.removeValue(forKey: identifier)
        if let transfer {
            let elapsed = max(0.001, Date().timeIntervalSince(transfer.startedAt))
            let rate = Double(transfer.bytesSent) * 8 / elapsed / 1_000_000
            logger.info(
                "HTTP \(transfer.fileName, privacy: .private) \(transfer.bytesSent, privacy: .public)/\(transfer.expectedBytes, privacy: .public) bytes · \(rate, format: .fixed(precision: 1), privacy: .public) Mb/s"
            )
        }
        guard transfer?.isTelemetryClient == true else { return transfer }
        if completed {
            completedTransfers += 1
        } else if expectedDisconnect {
            expectedDisconnects += 1
        } else {
            unexpectedErrors += 1
        }
        lastActivity = Date()
        emitTelemetry(force: true)
        return transfer
    }

    private func emitTelemetry(force: Bool) {
        guard let telemetryHandler else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastTelemetryEmission) >= 1.0 else { return }
        lastTelemetryEmission = now

        let measuredTransfers = transfers.values.filter(\.isTelemetryClient)
        let activeRates = measuredTransfers.compactMap { transfer -> Double? in
            let elapsed = now.timeIntervalSince(transfer.startedAt)
            guard transfer.bytesSent >= 524_288, elapsed >= 0.15 else { return nil }
            return Double(transfer.bytesSent) * 8 / elapsed
        }
        let capacityCandidates =
            recentCapacitySamples.isEmpty
            ? activeRates
            : recentCapacitySamples
        let observedCapacity: Double?
        if capacityCandidates.isEmpty {
            observedCapacity = nil
        } else {
            let sorted = capacityCandidates.sorted()
            observedCapacity = sorted[min(sorted.count - 1, (sorted.count * 3) / 4)]
        }
        let activeRate = activeRates.isEmpty ? nil : activeRates.reduce(0, +)

        telemetryHandler(
            HTTPServerTelemetry(
                totalBytesSent: totalBytesSent,
                activeTransfers: measuredTransfers.count,
                completedTransfers: completedTransfers,
                expectedDisconnects: expectedDisconnects,
                unexpectedErrors: unexpectedErrors,
                activeBitsPerSecond: activeRate,
                observedCapacityBitsPerSecond: observedCapacity,
                lastActivity: lastActivity
            ))
    }

    private func shouldMeasure(_ connection: NWConnection) -> Bool {
        guard let telemetryClientAddress else { return true }
        guard case .hostPort(let host, _) = connection.endpoint else { return false }
        let address: String
        switch host {
        case .ipv4(let value):
            address = value.debugDescription
        case .ipv6(let value):
            address = value.debugDescription
        case .name(let value, _):
            address = value
        @unknown default:
            return false
        }
        return address == telemetryClientAddress
    }

    private func send(
        status: Int,
        reason: String,
        body: Data,
        type: String,
        contentLength: Int? = nil,
        extraHeaders: [String] = [],
        keepAlive: Bool = false,
        bufferedRequestData: Data = Data(),
        on connection: NWConnection
    ) {
        var response = responseHeader(
            status: status,
            reason: reason,
            type: type,
            contentLength: contentLength ?? body.count,
            extraHeaders: extraHeaders,
            keepAlive: keepAlive
        )
        response.append(body)
        let responseSize = response.count
        connection.send(
            content: response,
            contentContext: keepAlive ? .defaultMessage : .finalMessage,
            isComplete: !keepAlive,
            completion: .contentProcessed { [weak self, logger] error in
                if let error {
                    logger.error(
                        "HTTP \(status, privacy: .public) falló al enviar \(responseSize, privacy: .public) bytes: \(String(describing: error), privacy: .public)"
                    )
                    connection.cancel()
                    return
                }
                if keepAlive {
                    self?.continueReceiving(on: connection, bufferedRequestData: bufferedRequestData)
                    return
                }
                self?.close(connection, after: 0.25)
            })
    }

    private func responseHeader(
        status: Int,
        reason: String,
        type: String,
        contentLength: Int,
        extraHeaders: [String],
        keepAlive: Bool
    ) -> Data {
        var headers = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(type)",
            "Content-Length: \(contentLength)",
            "Accept-Ranges: bytes",
            "Cache-Control: private, max-age=3600, immutable",
            "Connection: \(keepAlive ? "keep-alive" : "close")",
        ]
        if keepAlive {
            headers.append("Keep-Alive: timeout=15, max=1000")
        }
        headers += extraHeaders
        return Data((headers.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    private func byteRange(from header: String, total: Int) -> Range<Int>? {
        guard total > 0,
            let value = header.split(separator: ":", maxSplits: 1).last?
                .trimmingCharacters(in: .whitespaces),
            value.lowercased().hasPrefix("bytes=")
        else { return nil }

        let spec = value.dropFirst(6)
        guard !spec.contains(",") else { return nil }
        let parts = spec.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        if let start = Int(parts[0]) {
            let requestedEnd: Int
            if parts[1].isEmpty {
                requestedEnd = total - 1
            } else if let parsedEnd = Int(parts[1]) {
                requestedEnd = parsedEnd
            } else {
                return nil
            }
            let end = min(requestedEnd, total - 1)
            guard start >= 0, start <= end else { return nil }
            return start..<(end + 1)
        }

        if let suffixLength = Int(parts[1]), suffixLength > 0 {
            let start = max(0, total - suffixLength)
            return start..<total
        }

        return nil
    }

    private func mimeType(for extensionName: String) -> String {
        switch extensionName.lowercased() {
        case "m3u8": return "application/vnd.apple.mpegurl"
        case "ts": return "video/mp2t"
        case "m4s": return "video/iso.segment"
        case "mp4": return "video/mp4"
        case "vtt": return "text/vtt; charset=utf-8"
        default: return "application/octet-stream"
        }
    }

    private static func localIPv4Address(allowLoopback: Bool) -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }

        var candidates: [(priority: Int, address: String)] = []
        var current: UnsafeMutablePointer<ifaddrs>? = first

        while let interface = current {
            let flags = Int32(interface.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            if isUp, allowLoopback || !isLoopback,
                let address = interface.pointee.ifa_addr,
                address.pointee.sa_family == UInt8(AF_INET)
            {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = getnameinfo(
                    address,
                    socklen_t(address.pointee.sa_len),
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if result == 0 {
                    let name = host.withUnsafeBufferPointer { buffer in
                        guard let baseAddress = buffer.baseAddress else { return "" }
                        return decodeNullTerminatedUTF8(baseAddress)
                    }
                    let interfaceName = decodeNullTerminatedUTF8(interface.pointee.ifa_name)
                    let priority: Int
                    if interfaceName == "en0" {
                        priority = 0
                    } else if interfaceName.hasPrefix("en") {
                        priority = 1
                    } else if isLoopback {
                        priority = 3
                    } else {
                        priority = 2
                    }
                    candidates.append((priority, name))
                }
            }

            current = interface.pointee.ifa_next
        }

        return candidates.sorted { $0.priority < $1.priority }.first?.address
    }

    private static func decodeNullTerminatedUTF8(_ characters: UnsafePointer<CChar>) -> String {
        let bytes = UnsafeRawBufferPointer(start: characters, count: strlen(characters))
        return String(decoding: bytes, as: UTF8.self)
    }
}

private final class ContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ continuation: CheckedContinuation<URL, Error>, with result: Result<URL, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(with: result)
    }
}

private enum ServerError: LocalizedError {
    case noLocalAddress
    case cancelled
    case unexpectedEndOfFile

    var errorDescription: String? {
        switch self {
        case .noLocalAddress:
            return L10n.text(
                "No se encontró una dirección de red local. Conecta el Mac y el Apple TV a la misma red.")
        case .cancelled:
            return L10n.text("El servidor local se canceló antes de iniciarse.")
        case .unexpectedEndOfFile:
            return L10n.text("El archivo terminó antes de completar el rango solicitado.")
        }
    }
}
