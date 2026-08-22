import Foundation

enum MediaProbeService {
    static func probe(url: URL) async throws -> MediaProbe {
        try await Task.detached(priority: .userInitiated) {
            guard let ffprobeURL = Executables.find("ffprobe") else {
                throw AirCillerError.ffprobeMissing
            }

            let process = Process()
            process.executableURL = ffprobeURL
            process.arguments = [
                "-v", "error",
                "-show_entries",
                "format=duration,size,bit_rate:stream=index,codec_type,codec_name,profile,level,extradata,width,height,r_frame_rate,color_transfer,channels,channel_layout:stream_tags=language,title:stream_disposition=default,forced,hearing_impaired:stream_side_data:chapter=id,start_time,end_time:chapter_tags=title",
                "-show_data",
                "-of", "json",
                url.path,
            ]

            let output = Pipe()
            let errors = Pipe()
            let outputBuffer = ProcessDataBuffer()
            let errorBuffer = ProcessDataBuffer(maximumBytes: 64_000)
            output.fileHandleForReading.readabilityHandler = { handle in
                outputBuffer.append(handle.availableData)
            }
            errors.fileHandleForReading.readabilityHandler = { handle in
                errorBuffer.append(handle.availableData)
            }
            process.standardOutput = output
            process.standardError = errors
            try process.run()
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForWriting.close()
            process.waitUntilExit()
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            outputBuffer.append(output.fileHandleForReading.readDataToEndOfFile())
            errorBuffer.append(errors.fileHandleForReading.readDataToEndOfFile())

            guard process.terminationStatus == 0 else {
                let data = errorBuffer.snapshot
                let message = String(data: data, encoding: .utf8) ?? "ffprobe error"
                throw AirCillerError.probeFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
            }

            let data = outputBuffer.snapshot
            let response = try JSONDecoder().decode(ProbeResponse.self, from: data)
            guard let video = response.streams.first(where: { $0.codecType == "video" }) else {
                throw AirCillerError.noVideo
            }

            let sideData = video.sideDataList?.first(where: {
                $0.sideDataType.localizedCaseInsensitiveContains("DOVI")
            })

            let audioTracks = response.streams.compactMap { stream -> AudioTrack? in
                guard stream.codecType == "audio" else { return nil }
                return AudioTrack(
                    streamIndex: stream.index,
                    codec: stream.codecName ?? "unknown",
                    profile: stream.profile,
                    channels: stream.channels,
                    channelLayout: stream.channelLayout,
                    language: stream.tags?.language,
                    title: stream.tags?.title,
                    isDefault: stream.disposition?.defaultValue == 1
                )
            }

            var subtitleTracks = response.streams.compactMap { stream -> SubtitleTrack? in
                guard stream.codecType == "subtitle" else { return nil }
                return SubtitleTrack(
                    streamIndex: stream.index,
                    codec: stream.codecName ?? "unknown",
                    language: stream.tags?.language,
                    title: stream.tags?.title,
                    isDefault: stream.disposition?.defaultValue == 1,
                    isForced: stream.disposition?.forced == 1,
                    isHearingImpaired: stream.disposition?.hearingImpaired == 1,
                    externalPath: nil
                )
            }
            subtitleTracks.append(contentsOf: discoverExternalSubtitles(for: url))

            let chapters = (response.chapters ?? []).enumerated().compactMap { offset, chapter -> MediaChapter? in
                guard let start = Double(chapter.startTime), let end = Double(chapter.endTime) else { return nil }
                return MediaChapter(
                    id: offset,
                    start: start,
                    end: end,
                    title: chapter.tags?.title ?? "Capítulo \(offset + 1)"
                )
            }

            return MediaProbe(
                duration: Double(response.format?.duration ?? "") ?? 0,
                fileSize: Int64(response.format?.size ?? ""),
                bitRate: Int64(response.format?.bitRate ?? ""),
                videoStreamIndex: video.index,
                videoCodec: video.codecName ?? "unknown",
                videoProfile: video.profile,
                videoLevel: video.level,
                hevcCodecIdentifier: hevcCodecIdentifier(from: video),
                width: video.width,
                height: video.height,
                frameRate: video.frameRate,
                colorTransfer: video.colorTransfer,
                isDolbyVision: sideData != nil,
                dolbyVisionProfile: sideData?.dolbyVisionProfile,
                dolbyVisionLevel: sideData?.dolbyVisionLevel,
                dolbyVisionCompatibilityID: sideData?.dolbyVisionCompatibilityID,
                audioTracks: audioTracks,
                subtitleTracks: subtitleTracks,
                chapters: chapters
            )
        }.value
    }

    static func externalTrack(url: URL) -> SubtitleTrack {
        let extensionName = url.pathExtension.lowercased()
        let language = inferredLanguage(from: url.deletingPathExtension().lastPathComponent)
        return SubtitleTrack(
            streamIndex: nil,
            codec: extensionName == "srt" ? "subrip" : extensionName,
            language: language,
            title: url.deletingPathExtension().lastPathComponent,
            isDefault: false,
            isForced: url.lastPathComponent.localizedCaseInsensitiveContains("forced"),
            isHearingImpaired: url.lastPathComponent.localizedCaseInsensitiveContains("sdh"),
            externalPath: url.path
        )
    }

    private static func discoverExternalSubtitles(for videoURL: URL) -> [SubtitleTrack] {
        let directory = videoURL.deletingLastPathComponent()
        let base = videoURL.deletingPathExtension().lastPathComponent
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        else { return [] }

        let allowed = Set(["srt", "ass", "ssa", "vtt"])
        return
            files
            .filter { candidate in
                allowed.contains(candidate.pathExtension.lowercased())
                    && (candidate.deletingPathExtension().lastPathComponent == base
                        || candidate.deletingPathExtension().lastPathComponent.hasPrefix(base + ".")
                        || candidate.deletingPathExtension().lastPathComponent.hasPrefix(base + " "))
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map(externalTrack)
    }

    private static func inferredLanguage(from name: String) -> String? {
        let tokens = name.lowercased().split(whereSeparator: { $0 == "." || $0 == "_" || $0 == "-" })
        let known = Set([
            "es", "spa", "en", "eng", "fr", "fre", "fra", "de", "ger", "deu", "it", "ita", "pt", "por", "ca", "cat",
        ])
        return tokens.reversed().map(String.init).first(where: { known.contains($0) })
    }

    private static func hevcCodecIdentifier(from stream: ProbeStream) -> String? {
        guard stream.codecName?.lowercased() == "hevc",
            let dump = stream.extradata
        else { return nil }
        let bytes = extradataBytes(from: dump)
        guard bytes.count >= 13, bytes[0] == 1 else { return nil }

        let profileByte = bytes[1]
        let profileSpace = Int(profileByte >> 6)
        let tier = (profileByte & 0x20) != 0 ? "H" : "L"
        let profileIDC = Int(profileByte & 0x1F)
        let spacePrefix: String
        switch profileSpace {
        case 1: spacePrefix = "A"
        case 2: spacePrefix = "B"
        case 3: spacePrefix = "C"
        default: spacePrefix = ""
        }

        let compatibility = bytes[2...5]
            .map { String(format: "%02X", $0) }
            .joined()
        let level = Int(bytes[12])
        var constraintBytes = Array(bytes[6...11])
        while constraintBytes.last == 0 { constraintBytes.removeLast() }
        let constraints =
            constraintBytes
            .map { String(format: "%02X", $0) }
            .joined(separator: ".")

        var value = "hvc1.\(spacePrefix)\(profileIDC).\(compatibility).\(tier)\(level)"
        if !constraints.isEmpty { value += ".\(constraints)" }
        return value
    }

    private static func extradataBytes(from dump: String) -> [UInt8] {
        var bytes: [UInt8] = []
        for line in dump.components(separatedBy: .newlines) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let payload =
                line[line.index(after: colon)...]
                .components(separatedBy: "  ")
                .first ?? ""
            for group in payload.split(whereSeparator: { $0.isWhitespace }) {
                let text = String(group)
                guard text.count.isMultiple(of: 2),
                    text.allSatisfy({ $0.isHexDigit })
                else { continue }
                var index = text.startIndex
                while index < text.endIndex {
                    let end = text.index(index, offsetBy: 2)
                    if let byte = UInt8(text[index..<end], radix: 16) {
                        bytes.append(byte)
                    }
                    index = end
                }
            }
        }
        return bytes
    }
}

private struct ProbeResponse: Decodable {
    let streams: [ProbeStream]
    let format: ProbeFormat?
    let chapters: [ProbeChapter]?
}

private struct ProbeFormat: Decodable {
    let duration: String?
    let size: String?
    let bitRate: String?

    enum CodingKeys: String, CodingKey {
        case duration, size
        case bitRate = "bit_rate"
    }
}

private struct ProbeStream: Decodable {
    let index: Int
    let codecType: String?
    let codecName: String?
    let profile: String?
    let level: Int?
    let extradata: String?
    let width: Int?
    let height: Int?
    let frameRate: String?
    let colorTransfer: String?
    let channels: Int?
    let channelLayout: String?
    let tags: ProbeTags?
    let disposition: ProbeDisposition?
    let sideDataList: [ProbeSideData]?

    enum CodingKeys: String, CodingKey {
        case index, profile, level, extradata, width, height, channels, tags, disposition
        case codecType = "codec_type"
        case codecName = "codec_name"
        case frameRate = "r_frame_rate"
        case colorTransfer = "color_transfer"
        case channelLayout = "channel_layout"
        case sideDataList = "side_data_list"
    }
}

private struct ProbeTags: Decodable {
    let language: String?
    let title: String?
}

private struct ProbeDisposition: Decodable {
    let defaultValue: Int?
    let forced: Int?
    let hearingImpaired: Int?

    enum CodingKeys: String, CodingKey {
        case defaultValue = "default"
        case forced
        case hearingImpaired = "hearing_impaired"
    }
}

private struct ProbeSideData: Decodable {
    let sideDataType: String
    let dolbyVisionProfile: Int?
    let dolbyVisionLevel: Int?
    let dolbyVisionCompatibilityID: Int?

    enum CodingKeys: String, CodingKey {
        case sideDataType = "side_data_type"
        case dolbyVisionProfile = "dv_profile"
        case dolbyVisionLevel = "dv_level"
        case dolbyVisionCompatibilityID = "dv_bl_signal_compatibility_id"
    }
}

private struct ProbeChapter: Decodable {
    let id: Int64?
    let startTime: String
    let endTime: String
    let tags: ProbeTags?

    enum CodingKeys: String, CodingKey {
        case id, tags
        case startTime = "start_time"
        case endTime = "end_time"
    }
}

enum Executables {
    static func find(_ name: String) -> URL? {
        let candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/opt/local/bin/\(name)",
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map(URL.init(fileURLWithPath:))
    }
}
