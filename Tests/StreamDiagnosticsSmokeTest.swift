import Foundation

@main
struct StreamDiagnosticsSmokeTest {
    static func main() throws {
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

        print("Six-second peak, selected audio, network margin, and preparation ETA: OK")
    }
}
