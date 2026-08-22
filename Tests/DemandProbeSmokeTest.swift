import Foundation

@main
struct DemandProbeSmokeTest {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "DemandProbeSmokeTest.Usage", code: 2)
        }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let probe = try await MediaProbeService.probe(url: url)
        let analysis = try await StreamDemandAnalyzer.analyze(
            url: url,
            duration: probe.duration
        )
        let audio = probe.audioTracks.first(where: \.isDefault) ?? probe.audioTracks.first
        guard
            let profile = analysis.profile(
                videoStreamIndex: probe.videoStreamIndex,
                audioStreamIndex: audio?.streamIndex
            )
        else {
            throw NSError(domain: "DemandProbeSmokeTest.Profile", code: 3)
        }
        print(
            String(
                format: "%@ · media %.1f Mb/s · pico 6 s %.1f Mb/s · objetivo seguro %.1f Mb/s · %@",
                url.lastPathComponent,
                profile.averageBitsPerSecond / 1_000_000,
                (profile.peakBitsPerSecond ?? 0) / 1_000_000,
                (profile.safeTargetBitsPerSecond ?? 0) / 1_000_000,
                TimeFormatting.duration(profile.peakTime ?? 0)
            )
        )
    }
}
