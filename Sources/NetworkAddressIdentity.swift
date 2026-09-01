import Darwin
import Foundation

enum NetworkAddressIdentity {
    static func matches(_ lhs: String, _ rhs: String) -> Bool {
        canonical(lhs) == canonical(rhs)
    }

    static func canonical(_ value: String) -> String {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("["), candidate.hasSuffix("]") {
            candidate.removeFirst()
            candidate.removeLast()
        }

        let components = candidate.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
        let address = String(components[0])
        let scope = components.count == 2 ? String(components[1]).lowercased() : nil

        var ipv4 = in_addr()
        if address.withCString({ inet_pton(AF_INET, $0, &ipv4) }) == 1 {
            return numericIPv4(ipv4) ?? address
        }

        var ipv6 = in6_addr()
        if address.withCString({ inet_pton(AF_INET6, $0, &ipv6) }) == 1 {
            let bytes = withUnsafeBytes(of: &ipv6) { Array($0) }
            if bytes.prefix(12) == Array(repeating: 0, count: 10) + [0xFF, 0xFF] {
                var mapped = in_addr()
                withUnsafeMutableBytes(of: &mapped) { destination in
                    destination.copyBytes(from: bytes.suffix(4))
                }
                return numericIPv4(mapped) ?? address.lowercased()
            }
            let normalized = numericIPv6(ipv6) ?? address.lowercased()
            return scope.map { "\(normalized)%\($0)" } ?? normalized
        }

        return candidate.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func numericIPv4(_ address: in_addr) -> String? {
        var address = address
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        return buffer.withUnsafeBufferPointer { pointer in
            pointer.baseAddress.map(String.init(cString:))
        }
    }

    private static func numericIPv6(_ address: in6_addr) -> String? {
        var address = address
        var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &address, &buffer, socklen_t(buffer.count)) != nil else { return nil }
        return buffer.withUnsafeBufferPointer { pointer in
            pointer.baseAddress.map(String.init(cString:))
        }
    }
}
