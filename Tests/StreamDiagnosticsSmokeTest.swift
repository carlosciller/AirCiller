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
        progress.append("out_time_us=120000000\nspeed=12.5x\nprogress=continue\n")
        guard progress.seconds == 120, progress.speed == 12.5 else {
            throw NSError(domain: "StreamDiagnosticsSmokeTest.Progress", code: 4)
        }

        print("Pico de 6 s, audio elegido, margen de red y ETA de preparación: OK")
    }
}
