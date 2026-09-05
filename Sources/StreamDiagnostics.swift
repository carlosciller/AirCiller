import Foundation

struct StreamDemandProfile: Sendable, Equatable {
    let averageBitsPerSecond: Double
    let peakBitsPerSecond: Double?
    let peakTime: Double?
    let windowDuration: Double
    let isMeasured: Bool

    var safeTargetBitsPerSecond: Double? {
        peakBitsPerSecond.map { $0 * 1.5 }
    }

    var variabilityRatio: Double? {
        guard let peakBitsPerSecond, averageBitsPerSecond > 0 else { return nil }
        return peakBitsPerSecond / averageBitsPerSecond
    }
}

struct MediaDemandAnalysis: Sendable {
    let duration: Double
    let windowDuration: Double
    let bytesByStreamAndWindow: [Int: [Int: Int64]]
    let totalBytesByStream: [Int: Int64]

    func profile(
        videoStreamIndex: Int,
        audioStreamIndex: Int?,
        fixedAudioBitsPerSecond: Double? = nil
    ) -> StreamDemandProfile? {
        var streamIndices = [videoStreamIndex]
        if let audioStreamIndex { streamIndices.append(audioStreamIndex) }

        let totalBytes = streamIndices.reduce(0.0) {
            $0 + Double(totalBytesByStream[$1] ?? 0)
        }
        guard duration.isFinite, duration > 0, windowDuration.isFinite, windowDuration > 0,
            totalBytes > 0
        else { return nil }

        // A damaged timestamp must not turn a sparse packet map into billions
        // of empty iterations on the main actor.
        let windows = Set(streamIndices.flatMap { Array(bytesByStreamAndWindow[$0]?.keys ?? [:].keys) })
        var peak = 0.0
        var peakTime = 0.0
        for window in windows.sorted() where window >= 0 {
            let bytes = streamIndices.reduce(0.0) {
                $0 + Double(bytesByStreamAndWindow[$1]?[window] ?? 0)
            }
            let start = Double(window) * windowDuration
            guard start < duration else { continue }
            let measuredDuration = min(windowDuration, max(0.001, duration - start))
            let rate = Double(bytes) * 8 / measuredDuration
            if rate > peak {
                peak = rate
                peakTime = start
            }
        }

        let fixedAudio = max(0, fixedAudioBitsPerSecond ?? 0)
        return StreamDemandProfile(
            averageBitsPerSecond: Double(totalBytes) * 8 / duration + fixedAudio,
            peakBitsPerSecond: peak + fixedAudio,
            peakTime: peakTime,
            windowDuration: windowDuration,
            isMeasured: true
        )
    }
}

enum StreamDemandAnalyzer {
    static let windowDuration = 6.0

    static func analyze(url: URL, duration: Double) async throws -> MediaDemandAnalysis {
        do {
            guard let ffprobeURL = Executables.find("ffprobe") else {
                throw AirCillerError.ffprobeMissing
            }

            let process = Process()
            process.executableURL = ffprobeURL
            process.arguments = [
                "-v", "error",
                "-show_packets",
                "-show_entries", "packet=stream_index,pts_time,dts_time,size",
                "-of", "csv=p=0",
                url.path,
            ]

            let output = Pipe()
            let errors = Pipe()
            let packetAccumulator = PacketDemandAccumulator(
                duration: duration,
                windowDuration: windowDuration
            )
            let errorBuffer = ProcessDataBuffer(maximumBytes: 64_000)
            output.fileHandleForReading.readabilityHandler = { handle in
                packetAccumulator.append(handle.availableData)
            }
            errors.fileHandleForReading.readabilityHandler = { handle in
                errorBuffer.append(handle.availableData)
            }
            process.standardOutput = output
            process.standardError = errors
            let status = try await CancellableProcess(process).run {
                try? output.fileHandleForWriting.close()
                try? errors.fileHandleForWriting.close()
            }
            output.fileHandleForReading.readabilityHandler = nil
            errors.fileHandleForReading.readabilityHandler = nil
            packetAccumulator.append(output.fileHandleForReading.readDataToEndOfFile())
            errorBuffer.append(errors.fileHandleForReading.readDataToEndOfFile())
            try Task.checkCancellation()

            guard status == 0 else {
                let message = String(data: errorBuffer.snapshot, encoding: .utf8) ?? "ffprobe error"
                throw AirCillerError.probeFailed(
                    message.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }

            return packetAccumulator.snapshot
        }
    }

    static func packagedHLSProfile(
        outputDirectory: URL,
        hasSeparateAudio: Bool
    ) throws -> StreamDemandProfile {
        let videoSegments = try SubtitleService.parseVODPlaylist(
            at: outputDirectory.appendingPathComponent("video.m3u8")
        )
        let audioSegments =
            hasSeparateAudio
            ? try SubtitleService.parseVODPlaylist(
                at: outputDirectory.appendingPathComponent("audio.m3u8")
            )
            : []
        guard !videoSegments.isEmpty else {
            throw AirCillerError.invalidVODPackage("No hay segmentos para medir el caudal del stream.")
        }

        var totalBytes = 0.0
        var totalDuration = 0.0
        var peak = 0.0
        var peakTime = 0.0
        for (index, video) in videoSegments.enumerated() {
            let videoBytes = try fileSize(
                outputDirectory.appendingPathComponent(video.fileName)
            )
            let audioBytes =
                index < audioSegments.count
                ? try fileSize(outputDirectory.appendingPathComponent(audioSegments[index].fileName))
                : 0
            let bytes = videoBytes + audioBytes
            totalBytes += bytes
            totalDuration += video.duration
            let rate = bytes * 8 / max(video.duration, 0.001)
            if rate > peak {
                peak = rate
                peakTime = video.startTime
            }
        }

        return StreamDemandProfile(
            averageBitsPerSecond: totalBytes * 8 / max(totalDuration, 0.001),
            peakBitsPerSecond: peak,
            peakTime: peakTime,
            windowDuration: windowDuration,
            isMeasured: true
        )
    }

    static func directFileProfile(
        fileURL: URL,
        duration: Double,
        peakRatio: Double?
    ) throws -> StreamDemandProfile {
        let bytes = try fileSize(fileURL)
        let average = bytes * 8 / max(duration, 0.001)
        let ratio = min(max(peakRatio ?? 1.5, 1), 3)
        return StreamDemandProfile(
            averageBitsPerSecond: average,
            peakBitsPerSecond: average * ratio,
            peakTime: nil,
            windowDuration: windowDuration,
            isMeasured: peakRatio != nil
        )
    }

    static func estimatedProfile(probe: MediaProbe) -> StreamDemandProfile? {
        let average: Double?
        if let bitRate = probe.bitRate, bitRate > 0 {
            average = Double(bitRate)
        } else if let fileSize = probe.fileSize, fileSize > 0, probe.duration > 0 {
            average = Double(fileSize) * 8 / probe.duration
        } else {
            average = nil
        }
        guard let average else { return nil }
        return StreamDemandProfile(
            averageBitsPerSecond: average,
            peakBitsPerSecond: nil,
            peakTime: nil,
            windowDuration: windowDuration,
            isMeasured: false
        )
    }

    private static func fileSize(_ url: URL) throws -> Double {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize else {
            throw AirCillerError.invalidVODPackage(
                L10n.format("No se pudo medir %@.", url.lastPathComponent))
        }
        return Double(size)
    }
}

final class PacketDemandAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let duration: Double
    private let windowDuration: Double
    private var pendingText = ""
    private var bytesByStreamAndWindow: [Int: [Int: Int64]] = [:]
    private var totalBytesByStream: [Int: Int64] = [:]

    init(duration: Double, windowDuration: Double) {
        self.duration = duration
        self.windowDuration = windowDuration
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        let combined = pendingText + String(decoding: data, as: UTF8.self)
        let lines = combined.components(separatedBy: "\n")
        pendingText = lines.last ?? ""
        for line in lines.dropLast() { process(line) }
        lock.unlock()
    }

    var snapshot: MediaDemandAnalysis {
        lock.lock()
        if !pendingText.isEmpty {
            process(pendingText)
            pendingText = ""
        }
        let analysis = MediaDemandAnalysis(
            duration: duration,
            windowDuration: windowDuration,
            bytesByStreamAndWindow: bytesByStreamAndWindow,
            totalBytesByStream: totalBytesByStream
        )
        lock.unlock()
        return analysis
    }

    private func process(_ line: String) {
        let columns = line.split(separator: ",", omittingEmptySubsequences: false)
        guard columns.count >= 4,
            let streamIndex = Int(columns[0]),
            let size = Int64(columns[3])
        else { return }
        let presentationTime = Double(columns[1]) ?? Double(columns[2])
        guard let presentationTime, presentationTime.isFinite, presentationTime >= 0,
            size >= 0, streamIndex >= 0,
            let window = Int(exactly: floor(presentationTime / windowDuration))
        else { return }
        let (windowBytes, windowOverflow) = (bytesByStreamAndWindow[streamIndex]?[window] ?? 0)
            .addingReportingOverflow(size)
        let (totalBytes, totalOverflow) = (totalBytesByStream[streamIndex] ?? 0).addingReportingOverflow(size)
        guard !windowOverflow, !totalOverflow else { return }
        bytesByStreamAndWindow[streamIndex, default: [:]][window] = windowBytes
        totalBytesByStream[streamIndex] = totalBytes
    }
}

enum StreamHealthLevel: Sendable, Equatable {
    case pending
    case excellent
    case good
    case tight
    case insufficient
    case error
}

enum StreamHealth {
    static func level(
        capacity: Double?,
        demand: StreamDemandProfile?,
        unexpectedErrors: Int = 0
    ) -> StreamHealthLevel {
        if unexpectedErrors > 0 { return .error }
        guard let capacity, let peak = demand?.peakBitsPerSecond, peak > 0 else {
            return .pending
        }
        let ratio = capacity / peak
        if ratio < 1 { return .insufficient }
        if ratio < 1.25 { return .tight }
        if ratio < 1.5 { return .good }
        if ratio < 2 { return .good }
        return .excellent
    }

    static func label(capacity: Double?, demand: StreamDemandProfile?) -> String {
        guard let capacity, let peak = demand?.peakBitsPerSecond, peak > 0 else {
            return "Se medirá al reproducir"
        }
        let ratio = capacity / peak
        if ratio < 1 { return "Insuficiente" }
        if ratio < 1.25 { return "Muy justo" }
        if ratio < 1.5 { return "Suficiente" }
        if ratio < 2 { return "Holgado" }
        return "Excelente"
    }
}
