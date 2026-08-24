import Foundation

@main
struct LocalNetworkRouteSmokeTest {
    static func main() throws {
        let loopback = LocalNetworkRoute.ipv4Address(to: "127.0.0.1")
        let hostname = LocalNetworkRoute.ipv4Address(to: "not-an-address")
        let invalidIPv4 = LocalNetworkRoute.ipv4Address(to: "999.1.1.1")
        guard loopback == "127.0.0.1", hostname == nil, invalidIPv4 == nil
        else {
            throw NSError(
                domain: "LocalNetworkRouteSmokeTest",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "loopback=\(loopback ?? "nil"), hostname=\(hostname ?? "nil"), invalid=\(invalidIPv4 ?? "nil")"
                ]
            )
        }
        print("Receiver-specific local IPv4 route with safe fallback: OK")
    }
}
