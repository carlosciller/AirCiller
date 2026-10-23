import CryptoKit
import Foundation
import Observation
import Security

struct PrivateRemoteConfiguration: Decodable, Sendable {
    let endpoint: URL
    let agentToken: String
    let commandKey: Data
    let installationID: UUID
    let certificateSHA256: String

    func validate() throws {
        guard endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil,
            endpoint.password == nil, endpoint.query == nil, endpoint.fragment == nil,
            endpoint.path.isEmpty || endpoint.path == "/", commandKey.count == 32,
            agentToken.utf8.count >= 32, agentToken.utf8.count <= 256,
            agentToken.utf8.allSatisfy({ (33...126).contains($0) }),
            certificateSHA256.count == 64,
            certificateSHA256.allSatisfy({ $0.isHexDigit })
        else { throw URLError(.badURL) }
    }
}

private final class PrivateRemoteTrust: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let host: String
    let pin: String
    init(host: String, pin: String) {
        self.host = host.lowercased()
        self.pin = pin.lowercased()
    }

    func urlSession(
        _ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            challenge.protectionSpace.host.lowercased() == host,
            let trust = challenge.protectionSpace.serverTrust,
            let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        let digest = SHA256.hash(data: SecCertificateCopyData(leaf) as Data)
            .map { String(format: "%02x", $0) }.joined()
        guard digest == pin else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        // Anchor only this evaluation to the pinned private certificate and
        // retain hostname, validity and signature checks. Never change Keychain
        // trust settings or accept every certificate from the private network.
        guard SecTrustSetAnchorCertificates(trust, [leaf] as CFArray) == errSecSuccess,
            SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
            SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess,
            SecTrustEvaluateWithError(trust, nil)
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        // Trust only this privately provisioned exact certificate, not a global
        // trust exception. A changed certificate requires local reprovisioning.
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        urlSession(session, didReceive: challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

@MainActor
@Observable
final class PrivateRemoteClient {
    private struct Delivery: Decodable {
        let operationID: UUID
        let deliveryID: UUID
        let payload: Data
    }
    private struct Result: Encodable {
        let operationID: UUID
        let deliveryID: UUID
        let result: RemoteCommandGateway.Response
    }
    private let configuration: PrivateRemoteConfiguration
    private let gateway: RemoteCommandGateway
    private let session: URLSession
    private let trustDelegate: PrivateRemoteTrust
    private var task: Task<Void, Never>?
    private(set) var connectionState = "disabled"
    private(set) var lastTransportErrorCode: Int?

    init(configuration: PrivateRemoteConfiguration, coordinator: StreamCoordinator) throws {
        try configuration.validate()
        self.configuration = configuration
        gateway = try RemoteCommandGateway(
            coordinator: coordinator, installationID: configuration.installationID,
            key: configuration.commandKey)
        let settings = URLSessionConfiguration.ephemeral
        settings.httpCookieStorage = nil
        settings.urlCredentialStorage = nil
        settings.urlCache = nil
        settings.timeoutIntervalForRequest = 35
        settings.timeoutIntervalForResource = 40
        trustDelegate = PrivateRemoteTrust(host: configuration.endpoint.host!, pin: configuration.certificateSHA256)
        session = URLSession(configuration: settings, delegate: trustDelegate, delegateQueue: nil)
    }

    func start() {
        guard task == nil else { return }
        connectionState = "connecting"
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    let bytes = try await self.post("agent/poll", body: Data())
                    try Task.checkCancellation()
                    self.connectionState = "connected"
                    self.lastTransportErrorCode = nil
                    if let delivery = try JSONDecoder().decode(Delivery?.self, from: bytes) {
                        let result = try self.gateway.receive(
                            delivery.payload, expectedOperationID: delivery.operationID)
                        let encoded = try JSONEncoder().encode(
                            Result(
                                operationID: delivery.operationID,
                                deliveryID: delivery.deliveryID, result: result))
                        _ = try await self.post("agent/result", body: encoded)
                    }
                } catch {
                    if Task.isCancelled { return }
                    self.connectionState = "unavailable"
                    self.lastTransportErrorCode = (error as NSError).code
                    // No automatic command replay. Only reconnect the empty poll.
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                }
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        connectionState = "disabled"
    }

    private func post(_ path: String, body: Data) async throws -> Data {
        var request = URLRequest(url: configuration.endpoint.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("Bearer " + configuration.agentToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (stream, response) = try await session.bytes(for: request, delegate: trustDelegate)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        var data = Data()
        for try await byte in stream {
            guard data.count < 65_536 else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        return data
    }
}
