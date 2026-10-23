import CryptoKit
import Foundation

@main
enum DirectHDRSampleTableSmokeTest {
    private struct Failure: Error { let message: String }
    private struct Box {
        let type: String
        let start: Int
        let content: Int
        let end: Int
    }

    static func main() throws {
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--verify-file" {
            try verifyFile(
                source: URL(fileURLWithPath: CommandLine.arguments[2]),
                output: URL(fileURLWithPath: CommandLine.arguments[3]))
            return
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-direct-hdr-tables-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for use64 in [false, true] {
            for constantSizes in [false, true] {
                for splitMetadata in [false, true] where !constantSizes || !splitMetadata {
                    let file = directory.appendingPathComponent("table-\(use64)-\(constantSizes)-\(splitMetadata).mp4")
                    let original = fixture(use64: use64, constantSizes: constantSizes, splitMetadata: splitMetadata)
                    try original.write(to: file)
                    try require(try HDRConfigurationInjector.injectStaticMetadataIntoDirectFile(file), "No injection")
                    let injected = try Data(contentsOf: file)
                    try require(injected.count == original.count, "File length changed")
                    try require(mediaBox(injected) == mediaBox(original), "Media offsets changed")
                    let media = mediaBox(original)!
                    try require(injected[media] == original[media], "Multiplexed payload changed")
                    try require(tables(injected) == tables(original), "Sample tables changed")
                    let configuration = descendants(injected).first { $0.type == "hvcC" }!
                    let configurationBytes = injected[configuration.content..<configuration.end]
                    for nal in splitMetadata ? [masteringNAL, lightNAL] : [staticNAL] {
                        try require(configurationBytes.range(of: nal) != nil, "Static metadata not in hvcC")
                    }
                    try require(
                        !(try HDRConfigurationInjector.injectStaticMetadataIntoDirectFile(file)), "Not idempotent")
                }
            }
        }
        let noMetadata = directory.appendingPathComponent("no-metadata.mp4")
        let noMetadataBytes = fixture(use64: false, constantSizes: false, includeMetadata: false)
        try noMetadataBytes.write(to: noMetadata)
        do {
            _ = try HDRConfigurationInjector.injectStaticMetadataIntoDirectFile(noMetadata)
            throw Failure(message: "Audio's SEI-shaped bytes were accepted as video metadata")
        } catch HDRConfigurationInjector.InjectionError.missingStaticMetadata {}
        try require(try Data(contentsOf: noMetadata) == noMetadataBytes, "Failure changed original bytes")

        for corruption in ["offset", "count", "size", "run", "description", "nal"] {
            let file = directory.appendingPathComponent("invalid-\(corruption).mp4")
            var bytes = fixture(use64: true, constantSizes: false)
            let all = descendants(bytes)
            switch corruption {
            case "offset":
                let offset = all.first { $0.type == "co64" }!.content + 8
                bytes.replaceSubrange(offset..<(offset + 8), with: be64(UInt64.max))
            case "count":
                let offset = all.first { $0.type == "stsz" }!.content + 8
                bytes.replaceSubrange(offset..<(offset + 4), with: be32(UInt32.max))
            case "size":
                let offset = all.first { $0.type == "stsz" }!.content + 12
                bytes.replaceSubrange(offset..<(offset + 4), with: be32(UInt32.max))
            case "run":
                let offset = all.first { $0.type == "stsc" }!.content + 8
                bytes.replaceSubrange(offset..<(offset + 4), with: be32(0))
            case "description":
                let offset = all.first { $0.type == "stsc" }!.content + 16
                bytes.replaceSubrange(offset..<(offset + 4), with: be32(3))
            default:
                let offset = Int(uint(bytes, all.first { $0.type == "co64" }!.content + 8, 8))
                bytes.replaceSubrange(offset..<(offset + 4), with: be32(UInt32.max))
            }
            try bytes.write(to: file)
            do {
                _ = try HDRConfigurationInjector.injectStaticMetadataIntoDirectFile(file)
                throw Failure(message: "Invalid \(corruption) was accepted")
            } catch is HDRConfigurationInjector.InjectionError {}
            try require(try Data(contentsOf: file) == bytes, "Malformed input was modified")
        }
        print(
            "Direct HDR: track-bounded samples, stco/co64, chunk runs, fixed sizes, rejection and byte preservation: OK"
        )
    }

    private static let staticNAL = Data(
        [0x4E, 1, 137, 24] + Array(repeating: UInt8(1), count: 24)
            + [144, 4, 1, 2, 3, 4, 0x80])
    private static let masteringNAL = Data([0x4E, 1, 137, 24] + Array(repeating: UInt8(1), count: 24) + [0x80])
    private static let lightNAL = Data([0x4E, 1, 144, 4, 1, 2, 3, 4, 0x80])

    private static func fixture(
        use64: Bool, constantSizes: Bool, includeMetadata: Bool = true, splitMetadata: Bool = false
    ) -> Data {
        // Opaque audio begins with a sync word and contains a deliberately
        // oversized SEI-shaped sequence. It is never a sample of the HEVC track.
        var audio = Data([0x0B, 0x77, 0xFF, 0xFF, 0xFF])
        audio.append(be32(66_000))
        audio.append(Data([0x4E, 1, 137, 0, 0x80]))
        audio.append(Data(repeating: 0, count: 66_000 - 5))
        let plainNAL = Data([0x02, 1] + Array(repeating: UInt8(7), count: staticNAL.count - 2))
        let plain = be32(UInt32(plainNAL.count)) + plainNAL
        let hdrNAL = includeMetadata ? (splitMetadata ? masteringNAL : staticNAL) : plainNAL
        let hdr = be32(UInt32(hdrNAL.count)) + hdrNAL
        let third = splitMetadata ? be32(UInt32(lightNAL.count)) + lightNAL : (constantSizes ? hdr : hdr + plain)
        let payload = audio + plain + hdr + Data([0x0B, 0x77, 0, 0]) + third
        var config = Data(repeating: 0, count: 23)
        config[0] = 1
        config[21] = 3
        let descriptions = atom(
            "stsd",
            be32(0) + be32(2)
                + atom("avc1", Data(repeating: 0, count: 78))
                + atom("hvc1", Data(repeating: 0, count: 78) + atom("hvcC", config)))
        let sizes = atom(
            "stsz",
            be32(0) + be32(constantSizes ? UInt32(plain.count) : 0) + be32(3)
                + (constantSizes
                    ? Data() : be32(UInt32(plain.count)) + be32(UInt32(hdr.count)) + be32(UInt32(third.count))))
        let runs = atom(
            "stsc",
            be32(0) + be32(2) + be32(1) + be32(2) + be32(2)
                + be32(2) + be32(1) + be32(2))
        func movie(_ first: UInt64, _ second: UInt64) -> Data {
            let offsets = atom(
                use64 ? "co64" : "stco",
                be32(0) + be32(2)
                    + (use64 ? be64(first) + be64(second) : be32(UInt32(first)) + be32(UInt32(second))))
            return atom(
                "moov",
                atom(
                    "trak",
                    atom(
                        "mdia",
                        atom(
                            "minf",
                            atom(
                                "stbl",
                                descriptions + sizes + runs + offsets)))))
        }
        let ftyp = atom("ftyp", Data("isom".utf8) + be32(0))
        let padding = atom("free", Data(repeating: 0, count: 256))
        let mediaStart = ftyp.count + movie(0, 0).count + padding.count + 8
        let first = UInt64(mediaStart + audio.count)
        let second = first + UInt64(plain.count + hdr.count + 4)
        return ftyp + movie(first, second) + padding + atom("mdat", payload)
    }

    private static func verifyFile(source: URL, output: URL) throws {
        try require(!FileManager.default.fileExists(atPath: output.path), "Output must not exist")
        try FileManager.default.copyItem(at: source, to: output)
        let before = try prefix(source)
        let size = try FileManager.default.attributesOfItem(atPath: source.path)[.size] as! NSNumber
        guard let range = mediaBox(before, fileSize: size.intValue) else { throw Failure(message: "Missing mdat") }
        let payloadHash = try digest(source, from: range.lowerBound)
        let started = ContinuousClock.now
        let changed = try HDRConfigurationInjector.injectStaticMetadataIntoDirectFile(output)
        let elapsed = started.duration(to: .now)
        let after = try prefix(output)
        let newSize = try FileManager.default.attributesOfItem(atPath: output.path)[.size] as! NSNumber
        try require(changed && size == newSize, "Expected a same-size injection")
        try require(mediaBox(after, fileSize: newSize.intValue) == range, "mdat offset or length changed")
        try require(try digest(output, from: range.lowerBound) == payloadHash, "Media bytes changed")
        try require(tables(before) == tables(after), "Sample offsets/sizes/mapping changed")
        try require(!(try HDRConfigurationInjector.injectStaticMetadataIntoDirectFile(output)), "Not idempotent")
        print(
            "Direct HDR real fixture: injection \(elapsed); payload SHA256 \(payloadHash); all sample tables and size unchanged"
        )
    }

    private static func prefix(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try handle.read(upToCount: 32 * 1_024 * 1_024) ?? Data()
    }

    private static func digest(_ url: URL, from offset: Int) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        var result = SHA256()
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty { result.update(data: bytes) }
        return result.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func tables(_ data: Data) -> [Data] {
        descendants(data).filter { ["stco", "co64", "stsc", "stsz"].contains($0.type) }
            .map { Data(data[$0.start..<$0.end]) }
    }

    private static func descendants(_ data: Data) -> [Box] {
        func visit(_ range: Range<Int>) -> [Box] {
            var result: [Box] = []
            for box in boxes(data, range: range) {
                result.append(box)
                if ["moov", "trak", "mdia", "minf", "stbl"].contains(box.type) {
                    result += visit(box.content..<box.end)
                } else if box.type == "stsd" {
                    result += visit((box.content + 8)..<box.end)
                } else if ["hvc1", "hev1", "dvh1", "dvhe"].contains(box.type) {
                    result += visit((box.content + 78)..<box.end)
                }
            }
            return result
        }
        return visit(0..<data.count)
    }

    private static func mediaBox(_ data: Data, fileSize: Int? = nil) -> Range<Int>? {
        boxes(data, range: 0..<(fileSize ?? data.count)).first { $0.type == "mdat" }.map { $0.content..<$0.end }
    }

    private static func boxes(_ data: Data, range: Range<Int>) -> [Box] {
        var result: [Box] = []
        var start = range.lowerBound
        while start <= min(data.count, range.upperBound) - 8 {
            let compact = uint(data, start, 4)
            let header = compact == 1 ? 16 : 8
            guard start <= data.count - header else { break }
            let size =
                compact == 1
                ? uint(data, start + 8, 8)
                : (compact == 0 ? UInt64(range.upperBound - start) : compact)
            guard size >= header, size <= range.upperBound - start else { break }
            result.append(
                Box(
                    type: String(decoding: data[(start + 4)..<(start + 8)], as: UTF8.self),
                    start: start, content: start + header, end: start + Int(size)))
            start += Int(size)
        }
        return result
    }

    private static func atom(_ name: String, _ payload: Data) -> Data {
        be32(UInt32(payload.count + 8)) + Data(name.utf8) + payload
    }
    private static func uint(_ data: Data, _ offset: Int, _ count: Int) -> UInt64 {
        data[offset..<(offset + count)].reduce(0) { ($0 << 8) | UInt64($1) }
    }
    private static func be32(_ value: UInt32) -> Data {
        Data((0..<4).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    private static func be64(_ value: UInt64) -> Data {
        Data((0..<8).reversed().map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }
    private static func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw Failure(message: message) }
    }
}
