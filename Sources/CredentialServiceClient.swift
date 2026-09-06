import CryptoKit
import Foundation
import Security
@preconcurrency import XPC

/// Local builds opt in after explicitly preparing the stable, read-only service.
enum CredentialServiceClient {
    static let serviceName = "local.carlosciller.AirCiller.CredentialService"

    static var isRequired: Bool {
        Bundle.main.object(forInfoDictionaryKey: "ACCredentialServiceRequired") as? Bool == true
    }

    static func read(account: String, allowInteraction: Bool, operation: String = "read") throws -> String? {
        guard !account.isEmpty, account.utf8.count <= 256,
            account.utf8.allSatisfy({ $0 >= 32 && $0 != 127 })
        else { throw failure(errSecParam) }
        let signer = try ownCertificateFingerprint()
        let requirement = "identifier \"\(serviceName)\" and certificate leaf = H\"\(signer)\""
        try verifyService(requirement: requirement)
        let connection = xpc_connection_create(serviceName, nil)
        guard xpc_connection_set_peer_code_signing_requirement(connection, requirement) == 0 else {
            throw failure(errSecAuthFailed)
        }
        let response = CredentialServiceResponse()
        xpc_connection_set_event_handler(connection) { event in
            if xpc_get_type(event) == XPC_TYPE_ERROR { response.finish(data: nil, status: errSecNotAvailable) }
        }
        xpc_connection_activate(connection)
        defer { xpc_connection_cancel(connection) }
        let request = xpc_dictionary_create(nil, nil, 0)
        xpc_dictionary_set_int64(request, "version", 1)
        xpc_dictionary_set_string(request, "account", account)
        xpc_dictionary_set_string(request, "operation", operation)
        xpc_dictionary_set_bool(request, "allowInteraction", allowInteraction)
        xpc_connection_send_message_with_reply(connection, request, DispatchQueue.global(qos: .userInitiated)) {
            reply in
            guard xpc_get_type(reply) == XPC_TYPE_DICTIONARY,
                let statusValue = xpc_dictionary_get_value(reply, "status"),
                xpc_get_type(statusValue) == XPC_TYPE_INT64,
                let status = Int32(exactly: xpc_int64_get_value(statusValue))
            else {
                response.finish(data: nil, status: errSecNotAvailable)
                return
            }
            var count = 0
            let bytes = xpc_dictionary_get_data(reply, "credential", &count)
            guard count <= 16_384 else {
                response.finish(data: nil, status: errSecDecode)
                return
            }
            response.finish(data: bytes.map { Data(bytes: $0, count: count) }, status: status)
        }
        let result = response.wait(seconds: allowInteraction ? 65 : 8)
        if result.status == errSecItemNotFound { return nil }
        guard result.status == errSecSuccess else { throw failure(result.status) }
        if operation == "cleanupFixture" { return nil }
        guard let data = result.data, let credential = String(data: data, encoding: .utf8), !credential.isEmpty else {
            throw failure(errSecDecode)
        }
        return credential
    }

    private static func ownCertificateFingerprint() throws -> String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
            SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
            SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
            let info = information as? [String: Any],
            let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
            let certificate = certificates.first
        else { throw failure(errSecAuthFailed) }
        return Insecure.SHA1.hash(data: SecCertificateCopyData(certificate) as Data)
            .map { String(format: "%02x", $0) }.joined()
    }

    private static func verifyService(requirement text: String) throws {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/XPCServices/AirCillerCredentialService.xpc")
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
            SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
            SecStaticCodeCheckValidity(
                code, SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures), requirement)
                == errSecSuccess
        else { throw failure(errSecAuthFailed) }
    }

    private static func failure(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
}

/// XPC callbacks and the waiting credential actor share only this locked result.
private final class CredentialServiceResponse: @unchecked Sendable {
    private let lock = NSLock()
    private let ready = DispatchSemaphore(value: 0)
    private var result: (data: Data?, status: OSStatus)?

    func finish(data: Data?, status: OSStatus) {
        lock.lock()
        defer { lock.unlock() }
        guard result == nil else { return }
        result = (data, status)
        ready.signal()
    }

    func wait(seconds: Double) -> (data: Data?, status: OSStatus) {
        guard ready.wait(timeout: .now() + seconds) == .success else {
            finish(data: nil, status: errSecNotAvailable)
            return (nil, errSecNotAvailable)
        }
        lock.lock()
        defer { lock.unlock() }
        return result ?? (nil, errSecNotAvailable)
    }
}
