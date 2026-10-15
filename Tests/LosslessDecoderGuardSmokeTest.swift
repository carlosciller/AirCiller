import Foundation

@main
struct LosslessDecoderGuardSmokeTest {
    static func main() throws {
        for message in ["Invalid XLL sync word", "Forcing XLL recovery mode"] {
            let data = Data(("[dca @ 0x1] " + message + "\n").utf8)
            for boundary in 0...data.count {
                let guardState = LosslessDecoderGuard()
                guardState.append(Data(data.prefix(boundary)))
                guardState.append(Data(data.dropFirst(boundary)))
                try expect(guardState.failure == .recovery, "Recovery split at every pipe boundary")
                guardState.append(Data(repeating: 120, count: 20_000))
                try expect(guardState.failure == .recovery, "Later output cannot erase recovery")
            }
            let bytewise = LosslessDecoderGuard()
            for byte in data { bytewise.append(Data([byte])) }
            try expect(bytewise.failure == .recovery, "Single-byte reads retain the complete signature")
        }
        let clean = LosslessDecoderGuard()
        for _ in 0..<10_000 { clean.append(Data("Normal frame processing\n".utf8)) }
        try expect(clean.failure == nil, "Long valid decoding is accepted with bounded state")
        clean.append(Data([0xff, 0xfe, 0x00]))
        try expect(clean.failure == nil, "Invalid UTF-8 does not erase ASCII evidence")
        clean.append(Data("Invalid XLL sync word".utf8))
        try expect(clean.failure == .recovery, "Recovery after non-UTF8 bytes is still rejected")
        let oversized = LosslessDecoderGuard()
        oversized.append(Data(repeating: 0, count: 1_048_577))
        try expect(oversized.failure == .oversizedRead, "Oversized diagnostic reads fail closed")
        print("Lossless DTS guard: split reads, sticky recovery, bounded memory and raw-byte evidence: OK")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "LosslessDecoderGuard.\(message)", code: 1) }
    }
}
