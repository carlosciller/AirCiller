import Foundation

enum HDRConfigurationInjector {
    enum InjectionError: LocalizedError {
        case invalidInitializationSegment
        case invalidMediaSegment
        case missingStaticMetadata
        case unsupportedConfiguration

        var errorDescription: String? {
            switch self {
            case .invalidInitializationSegment:
                return "La cabecera fMP4 del vídeo no contiene una configuración HEVC válida."
            case .invalidMediaSegment:
                return "El primer fragmento HDR no contiene muestras HEVC válidas."
            case .missingStaticMetadata:
                return "No se encontraron los metadatos estáticos HDR10 del vídeo."
            case .unsupportedConfiguration:
                return "La configuración HEVC HDR es demasiado grande para la cabecera fMP4."
            }
        }
    }

    private struct MP4Box {
        let start: Int
        let size: Int
        let headerSize: Int
        let type: String

        var contentStart: Int { start + headerSize }
        var end: Int { start + size }
    }

    private static let containerTypes: Set<String> = [
        "moov", "trak", "mdia", "minf", "stbl",
    ]
    private static let visualSampleEntries: Set<String> = [
        "hvc1", "hev1", "dvh1", "dvhe",
    ]
    private static let staticSEITypes: Set<Int> = [137, 144, 147]

    /// Marks an initialization segment as an Apple-compatible fragmented-HLS
    /// file. FFmpeg emits generic ISO BMFF compatibility brands (`iso6`,
    /// `mp41`) while Apple's own HDR/Dolby Vision examples use `hlsf`.
    @discardableResult
    static func normalizeHLSFileType(initializationSegment: URL) throws -> Bool {
        var data = try Data(contentsOf: initializationSegment)
        guard let fileType = topLevelBoxes(in: data).first(where: { $0.type == "ftyp" }) else {
            throw InjectionError.invalidInitializationSegment
        }

        var normalized = Data()
        normalized.append(contentsOf: [0, 0, 0, 28])
        normalized.append(contentsOf: Array("ftyp".utf8))
        normalized.append(contentsOf: Array("iso5".utf8))
        normalized.append(contentsOf: [0, 0, 0, 1])
        normalized.append(contentsOf: Array("isom".utf8))
        normalized.append(contentsOf: Array("iso5".utf8))
        normalized.append(contentsOf: Array("hlsf".utf8))

        let current = Data(data[fileType.start..<fileType.end])
        guard current != normalized else { return false }
        data.replaceSubrange(fileType.start..<fileType.end, with: normalized)
        try data.write(to: initializationSegment, options: .atomic)
        return true
    }

    /// Adds the same HDR10 configuration to a regular MP4 without loading or
    /// moving its media payload. The direct-file muxer reserves a `free` box
    /// after `moov`; growing `hvcC` consumes a few bytes from that padding, so
    /// `mdat` and every absolute sample offset remain unchanged.
    @discardableResult
    static func injectStaticMetadataIntoDirectFile(_ file: URL) throws -> Bool {
        let handle = try FileHandle(forUpdating: file)
        defer { try? handle.close() }

        let fileSizeValue = try handle.seekToEnd()
        guard fileSizeValue <= UInt64(Int.max) else {
            throw InjectionError.unsupportedConfiguration
        }
        let fileSize = Int(fileSizeValue)
        let prefixLength = min(fileSize, 32 * 1024 * 1024)
        try handle.seek(toOffset: 0)
        guard var prefix = try handle.read(upToCount: prefixLength),
            prefix.count == prefixLength,
            let path = findBoxPath(type: "hvcC", in: prefix, range: 0..<prefix.count),
            let configuration = path.last,
            configuration.contentStart + 23 <= configuration.end
        else {
            throw InjectionError.invalidInitializationSegment
        }

        if configurationContainsStaticSEI(prefix, configuration: configuration) {
            return false
        }
        let lengthSize = Int(prefix[configuration.contentStart + 21] & 0x03) + 1
        guard
            let mediaStart = topLevelMediaDataContentStart(
                in: prefix,
                fileSize: fileSize
            ), mediaStart < prefix.endIndex
        else {
            throw InjectionError.invalidMediaSegment
        }
        let metadataNALUnits = try staticMetadataNALUnits(
            in: prefix,
            lengthSize: lengthSize,
            mediaPayloadRange: mediaStart..<prefix.endIndex
        )
        guard metadataNALUnits.count <= Int(UInt16.max),
            metadataNALUnits.allSatisfy({ $0.count <= Int(UInt16.max) })
        else {
            throw InjectionError.unsupportedConfiguration
        }

        var addition = Data()
        addition.append(0xA7)
        addition.append(contentsOf: bigEndianBytes(UInt16(metadataNALUnits.count)))
        for nalUnit in metadataNALUnits {
            addition.append(contentsOf: bigEndianBytes(UInt16(nalUnit.count)))
            addition.append(nalUnit)
        }
        let delta = addition.count

        guard let movie = topLevelBoxes(in: prefix).first(where: { $0.type == "moov" }),
            let padding = topLevelBoxes(in: prefix).first(where: {
                $0.type == "free" && $0.start == movie.end && $0.headerSize == 8
            }),
            padding.size >= delta + padding.headerSize,
            padding.size - delta <= Int(UInt32.max)
        else {
            throw InjectionError.unsupportedConfiguration
        }

        let arrayCountOffset = configuration.contentStart + 22
        guard prefix[arrayCountOffset] < UInt8.max else {
            throw InjectionError.unsupportedConfiguration
        }
        prefix[arrayCountOffset] += 1
        prefix.insert(contentsOf: addition, at: configuration.end)
        for box in path {
            guard box.headerSize == 8, box.size <= Int(UInt32.max) - delta else {
                throw InjectionError.unsupportedConfiguration
            }
            writeUInt32(UInt32(box.size + delta), to: &prefix, at: box.start)
        }

        let shiftedPaddingStart = padding.start + delta
        writeUInt32(UInt32(padding.size - delta), to: &prefix, at: shiftedPaddingStart)
        prefix.removeSubrange(padding.end..<(padding.end + delta))
        guard prefix.count == prefixLength else {
            throw InjectionError.unsupportedConfiguration
        }

        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: prefix)
        try handle.synchronize()
        return true
    }

    /// Copies the static HDR10 SEI messages from the first HEVC fragment into
    /// the HEVC decoder configuration record. Apple's HLS authoring rules
    /// expect mastering-display and content-light metadata in `hvcC`; FFmpeg's
    /// fMP4 HLS muxer otherwise leaves those messages only in media samples.
    @discardableResult
    static func injectStaticMetadata(
        initializationSegment: URL,
        firstMediaSegment: URL
    ) throws -> Bool {
        var initializationData = try Data(contentsOf: initializationSegment)
        let mediaData = try Data(contentsOf: firstMediaSegment)

        guard
            let path = findBoxPath(
                type: "hvcC",
                in: initializationData,
                range: 0..<initializationData.count
            ), let configuration = path.last
        else {
            throw InjectionError.invalidInitializationSegment
        }
        guard configuration.contentStart + 23 <= configuration.end else {
            throw InjectionError.invalidInitializationSegment
        }

        let lengthSize = Int(initializationData[configuration.contentStart + 21] & 0x03) + 1
        let metadataNALUnits = try staticMetadataNALUnits(
            in: mediaData,
            lengthSize: lengthSize
        )
        guard !metadataNALUnits.isEmpty else {
            throw InjectionError.missingStaticMetadata
        }

        if configurationContainsStaticSEI(
            initializationData,
            configuration: configuration
        ) {
            return false
        }

        guard metadataNALUnits.count <= Int(UInt16.max),
            metadataNALUnits.allSatisfy({ $0.count <= Int(UInt16.max) })
        else {
            throw InjectionError.unsupportedConfiguration
        }

        var addition = Data()
        // array_completeness=1, reserved=0, NAL_unit_type=39 (prefix SEI)
        addition.append(0xA7)
        addition.append(contentsOf: bigEndianBytes(UInt16(metadataNALUnits.count)))
        for nalUnit in metadataNALUnits {
            addition.append(contentsOf: bigEndianBytes(UInt16(nalUnit.count)))
            addition.append(nalUnit)
        }

        let arrayCountOffset = configuration.contentStart + 22
        let shiftsEmbeddedMedia = topLevelBoxes(in: initializationData).contains {
            $0.type == "mdat" && $0.start >= configuration.end
        }
        guard initializationData[arrayCountOffset] < UInt8.max else {
            throw InjectionError.unsupportedConfiguration
        }
        initializationData[arrayCountOffset] += 1
        initializationData.insert(contentsOf: addition, at: configuration.end)

        let delta = addition.count
        for box in path {
            guard box.headerSize == 8,
                box.size <= Int(UInt32.max) - delta
            else {
                throw InjectionError.unsupportedConfiguration
            }
            writeUInt32(UInt32(box.size + delta), to: &initializationData, at: box.start)
        }
        if shiftsEmbeddedMedia {
            try adjustChunkOffsets(
                in: &initializationData,
                range: 0..<initializationData.count,
                after: configuration.end,
                by: delta
            )
        }

        try initializationData.write(to: initializationSegment, options: .atomic)
        return true
    }

    /// Growing `moov` in a regular fast-start MP4 moves the following `mdat`.
    /// Its sample tables contain absolute file offsets, so every affected
    /// `stco`/`co64` entry must move by the same amount. Fragmented HLS init
    /// segments have no media data and therefore never enter this path.
    private static func adjustChunkOffsets(
        in data: inout Data,
        range: Range<Int>,
        after threshold: Int,
        by delta: Int
    ) throws {
        var offset = range.lowerBound
        while offset + 8 <= range.upperBound,
            let box = readBox(in: data, at: offset, limit: range.upperBound)
        {
            if box.type == "stco" || box.type == "co64" {
                guard box.contentStart + 8 <= box.end,
                    let countValue = readUInt32(data, at: box.contentStart + 4)
                else {
                    throw InjectionError.invalidInitializationSegment
                }
                let entrySize = box.type == "stco" ? 4 : 8
                let entriesStart = box.contentStart + 8
                let count = Int(countValue)
                guard count <= (box.end - entriesStart) / entrySize else {
                    throw InjectionError.invalidInitializationSegment
                }
                for index in 0..<count {
                    let entryOffset = entriesStart + index * entrySize
                    if box.type == "stco" {
                        guard let oldValue = readUInt32(data, at: entryOffset) else {
                            throw InjectionError.invalidInitializationSegment
                        }
                        guard
                            UInt64(oldValue) < UInt64(threshold)
                                || UInt64(oldValue) + UInt64(delta) <= UInt64(UInt32.max)
                        else {
                            throw InjectionError.unsupportedConfiguration
                        }
                        if UInt64(oldValue) >= UInt64(threshold) {
                            writeUInt32(oldValue + UInt32(delta), to: &data, at: entryOffset)
                        }
                    } else {
                        guard let oldValue = readUInt64(data, at: entryOffset),
                            oldValue < UInt64(threshold) || oldValue <= UInt64.max - UInt64(delta)
                        else {
                            throw InjectionError.unsupportedConfiguration
                        }
                        if oldValue >= UInt64(threshold) {
                            writeUInt64(oldValue + UInt64(delta), to: &data, at: entryOffset)
                        }
                    }
                }
            } else if containerTypes.contains(box.type) {
                try adjustChunkOffsets(
                    in: &data,
                    range: box.contentStart..<box.end,
                    after: threshold,
                    by: delta
                )
            }
            offset = box.end
        }
    }

    private static func findBoxPath(
        type target: String,
        in data: Data,
        range: Range<Int>,
        ancestors: [MP4Box] = []
    ) -> [MP4Box]? {
        var offset = range.lowerBound
        while offset + 8 <= range.upperBound,
            let box = readBox(in: data, at: offset, limit: range.upperBound)
        {
            let path = ancestors + [box]
            if box.type == target { return path }

            let childStart: Int?
            if containerTypes.contains(box.type) {
                childStart = box.contentStart
            } else if box.type == "stsd" {
                childStart = box.contentStart + 8
            } else if visualSampleEntries.contains(box.type) {
                childStart = box.contentStart + 78
            } else {
                childStart = nil
            }

            if let childStart, childStart < box.end,
                let result = findBoxPath(
                    type: target,
                    in: data,
                    range: childStart..<box.end,
                    ancestors: path
                )
            {
                return result
            }
            offset = box.end
        }
        return nil
    }

    private static func readBox(in data: Data, at offset: Int, limit: Int) -> MP4Box? {
        guard offset >= 0, offset + 8 <= limit,
            let compactSize = readUInt32(data, at: offset),
            let type = String(data: data[(offset + 4)..<(offset + 8)], encoding: .ascii)
        else {
            return nil
        }

        let headerSize: Int
        let size: Int
        if compactSize == 1 {
            guard offset + 16 <= limit,
                let extendedSize = readUInt64(data, at: offset + 8),
                extendedSize <= UInt64(Int.max)
            else { return nil }
            headerSize = 16
            size = Int(extendedSize)
        } else if compactSize == 0 {
            headerSize = 8
            size = limit - offset
        } else {
            headerSize = 8
            size = Int(compactSize)
        }
        guard size >= headerSize, offset + size <= limit else { return nil }
        return MP4Box(start: offset, size: size, headerSize: headerSize, type: type)
    }

    private static func staticMetadataNALUnits(
        in mediaData: Data,
        lengthSize: Int
    ) throws -> [Data] {
        guard (1...4).contains(lengthSize) else {
            throw InjectionError.invalidInitializationSegment
        }
        guard let mdat = topLevelBoxes(in: mediaData).first(where: { $0.type == "mdat" }) else {
            throw InjectionError.invalidMediaSegment
        }

        return try staticMetadataNALUnits(
            in: mediaData,
            lengthSize: lengthSize,
            mediaPayloadRange: mdat.contentStart..<mdat.end
        )
    }

    private static func staticMetadataNALUnits(
        in mediaData: Data,
        lengthSize: Int,
        mediaPayloadRange: Range<Int>
    ) throws -> [Data] {
        guard (1...4).contains(lengthSize),
            mediaPayloadRange.lowerBound >= 0,
            mediaPayloadRange.upperBound <= mediaData.count
        else {
            throw InjectionError.invalidMediaSegment
        }

        var result: [Data] = []
        var seen = Set<Data>()
        var offset = mediaPayloadRange.lowerBound
        while offset + lengthSize <= mediaPayloadRange.upperBound {
            let nalLength = readVariableUInt(mediaData, at: offset, count: lengthSize)
            offset += lengthSize
            guard nalLength > 0, nalLength <= mediaPayloadRange.upperBound - offset else { break }
            let nalUnit = Data(mediaData[offset..<(offset + nalLength)])
            offset += nalLength
            guard nalUnit.count >= 2 else { continue }
            let nalType = Int((nalUnit[0] >> 1) & 0x3F)
            guard nalType == 39,
                !staticSEIMessageTypes(in: nalUnit).isDisjoint(with: staticSEITypes),
                seen.insert(nalUnit).inserted
            else { continue }
            result.append(nalUnit)
        }

        // In a multiplexed fMP4 fragment, audio samples can interrupt the
        // length-prefixed HEVC sample sequence. Scan for valid prefix-SEI NAL
        // units when the fast sequential path did not find the HDR messages.
        if result.isEmpty {
            var candidateOffset = mediaPayloadRange.lowerBound
            while candidateOffset + lengthSize + 2 <= mediaPayloadRange.upperBound {
                let nalLength = readVariableUInt(
                    mediaData,
                    at: candidateOffset,
                    count: lengthSize
                )
                let nalStart = candidateOffset + lengthSize
                if nalLength >= 2,
                    nalLength <= mediaPayloadRange.upperBound - nalStart,
                    Int((mediaData[nalStart] >> 1) & 0x3F) == 39
                {
                    let nalUnit = Data(mediaData[nalStart..<(nalStart + nalLength)])
                    if !staticSEIMessageTypes(in: nalUnit).isDisjoint(with: staticSEITypes),
                        seen.insert(nalUnit).inserted
                    {
                        result.append(nalUnit)
                    }
                }
                candidateOffset += 1
            }
        }
        guard !result.isEmpty else { throw InjectionError.missingStaticMetadata }
        return result
    }

    private static func topLevelMediaDataContentStart(
        in data: Data,
        fileSize: Int
    ) -> Int? {
        var offset = 0
        while offset + 8 <= data.count {
            guard let compactSize = readUInt32(data, at: offset),
                let type = String(
                    data: data[(offset + 4)..<(offset + 8)],
                    encoding: .ascii
                )
            else { return nil }
            let headerSize: Int
            let size: Int
            if compactSize == 1 {
                guard offset + 16 <= data.count,
                    let extendedSize = readUInt64(data, at: offset + 8),
                    extendedSize <= UInt64(Int.max)
                else { return nil }
                headerSize = 16
                size = Int(extendedSize)
            } else if compactSize == 0 {
                headerSize = 8
                size = fileSize - offset
            } else {
                headerSize = 8
                size = Int(compactSize)
            }
            guard size >= headerSize, offset <= fileSize - size else { return nil }
            if type == "mdat" { return offset + headerSize }
            guard offset <= data.count - size else { return nil }
            offset += size
        }
        return nil
    }

    private static func staticSEIMessageTypes(in nalUnit: Data) -> Set<Int> {
        guard nalUnit.count > 3 else { return [] }
        let escaped = Array(nalUnit.dropFirst(2))
        var rbsp: [UInt8] = []
        rbsp.reserveCapacity(escaped.count)
        var zeroCount = 0
        for byte in escaped {
            if zeroCount >= 2, byte == 0x03 {
                zeroCount = 0
                continue
            }
            rbsp.append(byte)
            zeroCount = byte == 0 ? zeroCount + 1 : 0
        }

        var types = Set<Int>()
        var offset = 0
        while offset < rbsp.count {
            if rbsp[offset] == 0x80 { break }
            var payloadType = 0
            while offset < rbsp.count, rbsp[offset] == 0xFF {
                payloadType += 255
                offset += 1
            }
            guard offset < rbsp.count else { break }
            payloadType += Int(rbsp[offset])
            offset += 1

            var payloadSize = 0
            while offset < rbsp.count, rbsp[offset] == 0xFF {
                payloadSize += 255
                offset += 1
            }
            guard offset < rbsp.count else { break }
            payloadSize += Int(rbsp[offset])
            offset += 1
            guard payloadSize >= 0, offset + payloadSize <= rbsp.count else { break }
            types.insert(payloadType)
            offset += payloadSize
        }
        return types
    }

    private static func configurationContainsStaticSEI(
        _ data: Data,
        configuration: MP4Box
    ) -> Bool {
        var offset = configuration.contentStart + 23
        let count = Int(data[configuration.contentStart + 22])
        for _ in 0..<count {
            guard offset + 3 <= configuration.end else { return false }
            let nalType = Int(data[offset] & 0x3F)
            offset += 1
            guard let nalCount = readUInt16(data, at: offset) else { return false }
            offset += 2
            for _ in 0..<Int(nalCount) {
                guard let nalLength = readUInt16(data, at: offset) else { return false }
                offset += 2
                let length = Int(nalLength)
                guard offset + length <= configuration.end else { return false }
                if nalType == 39 {
                    let nal = Data(data[offset..<(offset + length)])
                    if !staticSEIMessageTypes(in: nal).isDisjoint(with: staticSEITypes) {
                        return true
                    }
                }
                offset += length
            }
        }
        return false
    }

    private static func topLevelBoxes(in data: Data) -> [MP4Box] {
        var boxes: [MP4Box] = []
        var offset = 0
        while offset + 8 <= data.count,
            let box = readBox(in: data, at: offset, limit: data.count)
        {
            boxes.append(box)
            offset = box.end
        }
        return boxes
    }

    private static func readVariableUInt(_ data: Data, at offset: Int, count: Int) -> Int {
        guard offset >= 0, count > 0, offset + count <= data.count else { return 0 }
        var value = 0
        for index in 0..<count { value = (value << 8) | Int(data[offset + index]) }
        return value
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= data.count else { return nil }
        return UInt16(data[offset]) << 8 | UInt16(data[offset + 1])
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset]) << 24 | UInt32(data[offset + 1]) << 16 | UInt32(data[offset + 2]) << 8
            | UInt32(data[offset + 3])
    }

    private static func readUInt64(_ data: Data, at offset: Int) -> UInt64? {
        guard offset >= 0, offset + 8 <= data.count else { return nil }
        var value: UInt64 = 0
        for index in 0..<8 { value = (value << 8) | UInt64(data[offset + index]) }
        return value
    }

    private static func writeUInt32(_ value: UInt32, to data: inout Data, at offset: Int) {
        data[offset] = UInt8((value >> 24) & 0xFF)
        data[offset + 1] = UInt8((value >> 16) & 0xFF)
        data[offset + 2] = UInt8((value >> 8) & 0xFF)
        data[offset + 3] = UInt8(value & 0xFF)
    }

    private static func writeUInt64(_ value: UInt64, to data: inout Data, at offset: Int) {
        for index in 0..<8 {
            let shift = UInt64((7 - index) * 8)
            data[offset + index] = UInt8((value >> shift) & 0xFF)
        }
    }

    private static func bigEndianBytes(_ value: UInt16) -> [UInt8] {
        [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]
    }
}
