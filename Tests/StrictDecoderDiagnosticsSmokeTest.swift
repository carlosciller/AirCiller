import Foundation

@main
struct StrictDecoderDiagnosticsSmokeTest {
    static func main() throws {
        let muxWarning = Data(
            "[hls @ 0x123abc] Stream 0 packet with pts 96000 has duration 0. The segment duration may not be precise.\n"
                .utf8)
        for split in 0...muxWarning.count {
            var policy = StrictDecoderDiagnosticPolicy()
            policy.append(Data(muxWarning.prefix(split)))
            policy.append(Data(muxWarning.dropFirst(split)))
            try expect(policy.finish(), "Exact pinned empty-FLAC-packet warning across split reads")
        }
        for message in [
            "[truehd @ 0x123abc] Lossless check failed - expected ff, calculated a4.\n",
            "[truehd @ 0x123abc] Stream parameters not seen; skipping frame.\n",
            String(decoding: muxWarning, as: UTF8.self).replacingOccurrences(of: "[hls @", with: "[truehd @"),
            String(decoding: muxWarning, as: UTF8.self).replacingOccurrences(of: "duration 0.", with: "duration 1."),
            String(repeating: "x", count: 2_049),
        ] {
            var policy = StrictDecoderDiagnosticPolicy()
            policy.append(muxWarning)
            policy.append(Data(message.utf8))
            try expect(!policy.finish(), "No broad warning exception, and decoder rejection remains sticky")
        }
        for payload in [Data(), Data("Decoder error despite exit zero\n".utf8), Data([0xFF])] {
            let pipe = Pipe()
            let log = ProcessLogBuffer()
            let reader = try StrictDecoderDiagnostics(handle: pipe.fileHandleForReading, log: log)
            try pipe.fileHandleForWriting.write(contentsOf: payload)
            try pipe.fileHandleForWriting.close()
            try expect(reader.finish() == payload.isEmpty, "Final bytes must be consumed, including non-UTF8 errors")
            try expect(!reader.finish(), "A repeated finish cannot certify a closed stream")
            reader.close()
            reader.start()
            reader.close()
        }
        let incomplete = Pipe()
        let reader = try StrictDecoderDiagnostics(handle: incomplete.fileHandleForReading, log: ProcessLogBuffer())
        reader.start()
        reader.start()
        try expect(!reader.finish(), "Open writer is incomplete, not clean decoding")
        try incomplete.fileHandleForWriting.close()
        for _ in 0..<128 {
            let pipe = Pipe()
            let reader = try StrictDecoderDiagnostics(handle: pipe.fileHandleForReading, log: ProcessLogBuffer())
            reader.start()
            try pipe.fileHandleForWriting.write(contentsOf: Data("early error\n".utf8))
            try pipe.fileHandleForWriting.close()
            try expect(!reader.finish(), "Callback/final drain race cannot erase errors")
        }
        print(
            "Strict TrueHD diagnostics: empty EOF, final error bytes, non-UTF8, incomplete writers and reader races: OK"
        )
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "StrictDecoderDiagnostics.\(message)", code: 1) }
    }
}
