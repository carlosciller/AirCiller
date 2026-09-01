import Foundation

@main
struct NetworkAddressIdentitySmokeTest {
    static func main() throws {
        guard NetworkAddressIdentity.matches(" 198.51.100.33 ", "198.51.100.33"),
            NetworkAddressIdentity.matches("198.51.100.33", "::ffff:198.51.100.33"),
            NetworkAddressIdentity.matches("[2001:0DB8::1]", "2001:db8:0:0:0:0:0:1"),
            NetworkAddressIdentity.matches("Apple-TV.local.", "apple-tv.LOCAL"),
            NetworkAddressIdentity.matches("fe80::1%EN0", "fe80:0:0:0:0:0:0:1%en0"),
            !NetworkAddressIdentity.matches("fe80::1%en0", "fe80::1%en1"),
            !NetworkAddressIdentity.matches("198.51.100.33", "198.51.100.34")
        else {
            throw NSError(domain: "NetworkAddressIdentitySmokeTest", code: 1)
        }

        print("IPv4, mapped IPv6, scoped IPv6, and receiver names normalize safely: OK")
    }
}
