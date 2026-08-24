import Foundation

@main
struct ProbeSmokeTest {
    static func main() async throws {
        guard CommandLine.arguments.count > 1 else {
            throw NSError(domain: "ProbeSmokeTest", code: 2)
        }
        for path in CommandLine.arguments.dropFirst() {
            let url = URL(fileURLWithPath: path)
            let probe = try await MediaProbeService.probe(url: url)
            let atmos = probe.audioTracks.filter(\.isAtmos).count
            let textSubtitles = probe.subtitleTracks.filter(\.isTextBased).count
            let graphicSubtitles = probe.subtitleTracks.count - textSubtitles
            print(
                [
                    url.lastPathComponent,
                    "duration=\(Int(probe.duration))",
                    "dv=\(probe.dolbyVisionProfile.map(String.init) ?? "no")",
                    "audio=\(probe.audioTracks.count)",
                    "atmos=\(atmos)",
                    "textSubs=\(textSubtitles)",
                    "graphicSubs=\(graphicSubtitles)",
                    "chapters=\(probe.chapters.count)",
                ].joined(separator: " | "))
            for audio in probe.audioTracks {
                print("  audio \(audio.streamIndex): \(audio.displayName) · \(audio.technicalDescription)")
            }
            for subtitle in probe.subtitleTracks {
                print("  subtitles \(subtitle.streamIndex.map(String.init) ?? "external"): \(subtitle.displayName)")
            }
        }
    }
}
