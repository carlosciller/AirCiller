import Darwin
import Foundation

@main
struct StreamDiagnosticsSmokeTest {
    static func pipeIdentity(_ descriptor: Int32) throws -> UInt64? {
        var info = pipe_fdinfo()
        errno = 0
        let size = proc_pidfdinfo(
            getpid(), descriptor, PROC_PIDFDPIPEINFO, &info, Int32(MemoryLayout<pipe_fdinfo>.size))
        if size == MemoryLayout<pipe_fdinfo>.size { return info.pipeinfo.pipe_handle }
        if size == 0 && errno == EBADF { return nil }
        throw NSError(domain: "StreamDiagnosticsSmokeTest.PipeInspection", code: Int(errno))
    }

    @MainActor
    static func cancelledAnalysisClosesPipes() async throws {
        guard let engine = ProcessInfo.processInfo.environment["AIRCILLER_TEST_FFPROBE"] else {
            throw NSError(domain: "StreamDiagnosticsSmokeTest.Engine", code: 10)
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("AirCiller-DemandCancel-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let fifo = root.appendingPathComponent("input.mkv")
        guard mkfifo(fifo.path, 0o600) == 0 else {
            throw NSError(domain: "StreamDiagnosticsSmokeTest.FIFO", code: 11)
        }
        let watchdog = DispatchWorkItem { _exit(2) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: watchdog)
        defer { watchdog.cancel() }
        for _ in 0..<3 {
            let started = AsyncStream<(Process, FileHandle, FileHandle)>.makeStream()
            let task = Task {
                try await StreamDemandAnalyzer.analyze(
                    url: fifo, duration: 60, ffprobeURL: URL(fileURLWithPath: engine),
                    onStarted: { process in
                        let output = process.standardOutput as! Pipe
                        let errors = process.standardError as! Pipe
                        started.continuation.yield(
                            (
                                process, output.fileHandleForReading,
                                errors.fileHandleForReading
                            ))
                    })
            }
            var iterator = started.stream.makeAsyncIterator()
            guard let (process, outputReader, errorReader) = await iterator.next(), process.isRunning else {
                throw NSError(domain: "StreamDiagnosticsSmokeTest.NotRunning", code: 12)
            }
            let outputFD = outputReader.fileDescriptor
            let errorFD = errorReader.fileDescriptor
            // Pin the pipe identities while checking the original descriptors.
            // A reused descriptor cannot identify a leak, and the anchors keep
            // the original kernel pipe identities from being recycled.
            let outputAnchor = dup(outputFD)
            let errorAnchor = dup(errorFD)
            defer {
                if outputAnchor >= 0 { close(outputAnchor) }
                if errorAnchor >= 0 { close(errorAnchor) }
            }
            guard outputAnchor >= 0, errorAnchor >= 0,
                let outputIdentity = try pipeIdentity(outputAnchor),
                let errorIdentity = try pipeIdentity(errorAnchor)
            else { throw NSError(domain: "StreamDiagnosticsSmokeTest.PipeAnchors", code: 16) }
            let began = ContinuousClock.now
            task.cancel()
            do {
                _ = try await task.value
                throw NSError(domain: "StreamDiagnosticsSmokeTest.Uncancelled", code: 13)
            } catch is CancellationError {}
            started.continuation.finish()
            // Foundation retires an active readability source asynchronously.
            // Keep the original three-second bound for child and pipe cleanup;
            // inspect pinned identities so unrelated reused descriptors are safe.
            while began.duration(to: .now) < .seconds(3) {
                let outputRetired = try pipeIdentity(outputFD) != outputIdentity
                let errorRetired = try pipeIdentity(errorFD) != errorIdentity
                if outputRetired && errorRetired { break }
                try await Task.sleep(for: .milliseconds(1))
            }
            let running = process.isRunning
            let elapsed = began.duration(to: .now)
            let outputClosed = try pipeIdentity(outputFD) != outputIdentity
            let errorClosed = try pipeIdentity(errorFD) != errorIdentity
            guard !running, elapsed < .seconds(3), outputClosed, errorClosed
            else {
                throw NSError(
                    domain: "StreamDiagnosticsSmokeTest.LeakedProcessOrPipe", code: 14,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "running=\(running), elapsed=\(elapsed), outputClosed=\(outputClosed), errorClosed=\(errorClosed)"
                    ])
            }
        }
        print("Demand cancellation reaps real ffprobe and closes both read pipes: OK")
    }

    @MainActor
    static func main() async throws {
        try await cancelledAnalysisClosesPipes()
        let preparedFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data(repeating: 0, count: 6000).write(to: preparedFile)
        defer { try? FileManager.default.removeItem(at: preparedFile) }
        let estimated = try StreamDemandAnalyzer.directFileProfile(fileURL: preparedFile, duration: 6, peakRatio: nil)
        let measured = try StreamDemandAnalyzer.directFileProfile(fileURL: preparedFile, duration: 6, peakRatio: 2)
        guard !estimated.isMeasured, estimated.peakTime == nil, estimated.peakBitsPerSecond == 12_000,
            measured.isMeasured, measured.peakBitsPerSecond == 16_000
        else { throw NSError(domain: "StreamDiagnosticsSmokeTest.EstimateProvenance", code: 15) }
        let analysis = MediaDemandAnalysis(
            duration: 18,
            windowDuration: 6,
            bytesByStreamAndWindow: [
                0: [0: 9_000_000, 1: 18_000_000, 2: 12_000_000],
                1: [0: 480_000, 1: 480_000, 2: 480_000],
            ],
            totalBytesByStream: [0: 39_000_000, 1: 1_440_000]
        )
        guard
            let profile = analysis.profile(
                videoStreamIndex: 0,
                audioStreamIndex: 1
            )
        else {
            throw NSError(domain: "StreamDiagnosticsSmokeTest.Profile", code: 1)
        }
        guard abs(profile.averageBitsPerSecond - 17_973_333.333) < 1,
            abs((profile.peakBitsPerSecond ?? 0) - 24_640_000) < 1,
            profile.peakTime == 6,
            abs((profile.safeTargetBitsPerSecond ?? 0) - 36_960_000) < 1
        else {
            throw NSError(domain: "StreamDiagnosticsSmokeTest.Measurement", code: 2)
        }

        guard StreamHealth.level(capacity: 80_000_000, demand: profile) == .excellent,
            StreamHealth.level(capacity: 28_000_000, demand: profile) == .tight,
            StreamHealth.level(capacity: 20_000_000, demand: profile) == .insufficient,
            StreamHealth.level(capacity: nil, demand: profile) == .pending,
            StreamHealth.level(capacity: 80_000_000, demand: profile, unexpectedErrors: 1) == .error
        else {
            throw NSError(domain: "StreamDiagnosticsSmokeTest.Health", code: 3)
        }

        let progress = ProcessProgressBuffer()
        let sparse = MediaDemandAnalysis(
            duration: 18, windowDuration: 6,
            bytesByStreamAndWindow: [0: [0: 600, 1_000_000_000: 600]],
            totalBytesByStream: [0: 1200]
        )
        guard sparse.profile(videoStreamIndex: 0, audioStreamIndex: nil)?.peakTime == 0 else {
            throw NSError(domain: "StreamDiagnosticsSmokeTest.SparseTimestamps", code: 5)
        }
        let accumulator = PacketDemandAccumulator(duration: 18, windowDuration: 6)
        accumulator.append(Data("0,1e100,N/A,10\n0,nan,N/A,10\n0,0,N/A,-1\n0,0,N/A,600\n".utf8))
        guard accumulator.snapshot.totalBytesByStream == [0: 600] else {
            throw NSError(domain: "StreamDiagnosticsSmokeTest.InvalidPacket", code: 6)
        }
        accumulator.append(Data("0,0,N/A,9223372036854775807\n".utf8))
        guard accumulator.snapshot.totalBytesByStream == [0: 600] else {
            throw NSError(domain: "StreamDiagnosticsSmokeTest.Overflow", code: 7)
        }
        progress.append("out_time_us=120000000\nspeed=12.5x\nprogress=continue\n")
        guard progress.seconds == 120, progress.speed == 12.5 else {
            throw NSError(domain: "StreamDiagnosticsSmokeTest.Progress", code: 4)
        }
        try adjustedRenditionDemand()
        try differentUnadjustedSegmentBoundaries()

        print("Six-second peak, selected audio, network margin, and preparation ETA: OK")
    }

    private static func adjustedRenditionDemand() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["video-0.m4s", "video-1.m4s"] {
            try Data(repeating: 0, count: 6000).write(to: directory.appendingPathComponent(name))
        }
        for name in ["audio-0.m4s", "audio-1.m4s"] {
            try Data(repeating: 0, count: 1000).write(to: directory.appendingPathComponent(name))
        }
        let video = """
            #EXTM3U
            #EXT-X-VERSION:8
            #EXT-X-TARGETDURATION:6
            #EXTINF:6,
            video-0.m4s
            #EXTINF:6,
            video-1.m4s
            #EXT-X-ENDLIST
            """
        let audio = """
            #EXTM3U
            #EXT-X-VERSION:8
            #EXT-X-TARGETDURATION:6
            #EXT-X-GAP
            #EXTINF:2,
            audio-leading-gap.m4s
            #EXTINF:5,
            audio-0.m4s
            #EXTINF:5,
            audio-1.m4s
            #EXT-X-ENDLIST
            """
        try video.write(to: directory.appendingPathComponent("video.m3u8"), atomically: true, encoding: .utf8)
        try audio.write(to: directory.appendingPathComponent("audio.m3u8"), atomically: true, encoding: .utf8)
        let info = HLSAudioTimelineInfo(
            version: 1, sourceDuration: 12, presentationDuration: 12,
            timestampOrigin: 10, videoContentOffset: 0)
        try JSONEncoder().encode(info).write(to: directory.appendingPathComponent(HLSAudioTimelineInfo.fileName))
        let result = try StreamDemandAnalyzer.packagedHLSProfile(outputDirectory: directory, hasSeparateAudio: true)
        guard abs(result.averageBitsPerSecond - 14_000 * 8.0 / 12) < 0.001,
            abs((result.peakBitsPerSecond ?? 0) - 9600) < 0.001,
            result.windowDuration == 6
        else { throw NSError(domain: "StreamDiagnosticsSmokeTest.AdjustedRenditions", code: 8) }
    }

    private static func differentUnadjustedSegmentBoundaries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        func rendition(_ kind: String, durations: [Int], sizes: [Int]) throws {
            var lines = ["#EXTM3U", "#EXT-X-VERSION:7", "#EXT-X-PLAYLIST-TYPE:VOD"]
            for (index, duration) in durations.enumerated() {
                let name = "\(kind)-\(index).m4s"
                try Data(repeating: 0, count: sizes[index]).write(to: directory.appendingPathComponent(name))
                lines += ["#EXTINF:\(duration),", name]
            }
            lines.append("#EXT-X-ENDLIST")
            try lines.joined(separator: "\n").write(
                to: directory.appendingPathComponent("\(kind).m3u8"), atomically: true, encoding: .utf8)
        }
        // Keyframes produce ten-second video segments; audio segments stay at
        // five seconds. The largest audio segment occurs after the video index ends.
        try rendition("video", durations: [10, 10], sizes: [10_000, 10_000])
        try rendition("audio", durations: [5, 5, 5, 5], sizes: [1_000, 1_000, 1_000, 10_000])
        let profile = try StreamDemandAnalyzer.packagedHLSProfile(outputDirectory: directory, hasSeparateAudio: true)
        guard abs(profile.averageBitsPerSecond - 13_200) < 0.001,
            abs((profile.peakBitsPerSecond ?? 0) - 21_600) < 0.001,
            profile.peakTime == 14, profile.windowDuration == 6
        else {
            throw NSError(
                domain: "StreamDiagnosticsSmokeTest.UnalignedRenditions", code: 9,
                userInfo: [NSLocalizedDescriptionKey: String(describing: profile)])
        }
    }
}
