import Darwin
import Foundation

/// Resolves the IPv4 source address macOS would use for a specific receiver.
/// A connected UDP socket selects a route without sending any packet.
enum LocalNetworkRoute {
    static func ipv4Address(to remoteAddress: String, port: UInt16 = 7000) -> String? {
        var destination = sockaddr_in()
        destination.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        destination.sin_family = sa_family_t(AF_INET)
        destination.sin_port = port.bigEndian
        let parsed = remoteAddress.withCString { pointer in
            inet_pton(AF_INET, pointer, &destination.sin_addr)
        }
        guard parsed == 1 else { return nil }

        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        let connected = withUnsafePointer(to: &destination) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                Darwin.connect(
                    descriptor,
                    address,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard connected == 0 else { return nil }

        var local = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let resolved = withUnsafeMutablePointer(to: &local) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { address in
                getsockname(descriptor, address, &length)
            }
        }
        guard resolved == 0, local.sin_family == sa_family_t(AF_INET) else { return nil }

        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &local.sin_addr, &buffer, socklen_t(buffer.count)) != nil else {
            return nil
        }
        return buffer.withUnsafeBufferPointer { pointer in
            guard let baseAddress = pointer.baseAddress else { return nil }
            return String(cString: baseAddress)
        }
    }
}
