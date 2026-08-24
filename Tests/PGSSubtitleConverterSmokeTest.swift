import Foundation

@main
struct PGSSubtitleConverterSmokeTest {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let fullTrack = arguments.contains("--full")
        let inputPath =
            arguments.first(where: { !$0.hasPrefix("--") })
            ?? ProcessInfo.processInfo.environment["AIRCILLER_TEST_PGS_MEDIA"]
        guard let inputPath, FileManager.default.fileExists(atPath: inputPath) else {
            throw NSError(
                domain: "PGSSubtitleConverterSmokeTest.Input",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Provide a file containing PGS as an argument "
                        + "or through AIRCILLER_TEST_PGS_MEDIA."
                ]
            )
        }
        let input = URL(fileURLWithPath: inputPath)
        let probe = try await MediaProbeService.probe(url: input)
        guard let track = probe.subtitleTracks.first(where: \.usesBitmapOCR) else {
            throw NSError(domain: "PGSSubtitleConverterSmokeTest.Track", code: 2)
        }
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-PGS-Test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }

        let conversion = try await PGSSubtitleConverter.convert(
            track: track,
            videoURL: input,
            videoDuration: probe.duration,
            maximumRenderedFrames: fullTrack ? nil : 8,
            cacheDirectory: cacheDirectory
        )
        guard conversion.cueCount >= 1,
            conversion.averageConfidence >= 0.45,
            conversion.webVTT.hasPrefix("WEBVTT\n"),
            conversion.webVTT.contains(" --> "),
            conversion.webVTT.contains("line:") && conversion.webVTT.contains("position:")
        else {
            throw NSError(
                domain: "PGSSubtitleConverterSmokeTest.Conversion",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unexpected PGS conversion:\n\(conversion.webVTT)"]
            )
        }
        if fullTrack {
            guard conversion.cueCount >= 1 else {
                throw NSError(
                    domain: "PGSSubtitleConverterSmokeTest.FullTrack",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Only \(conversion.cueCount) cues were recognized."]
                )
            }
            let cached = try await PGSSubtitleConverter.convert(
                track: track,
                videoURL: input,
                videoDuration: probe.duration,
                cacheDirectory: cacheDirectory
            )
            guard cached.usedCache,
                cached.webVTT == conversion.webVTT,
                cached.cueCount == conversion.cueCount
            else {
                throw NSError(domain: "PGSSubtitleConverterSmokeTest.Cache", code: 4)
            }
            print(
                "Complete PGS · \(conversion.cueCount) cues · OCR \(Int(conversion.averageConfidence * 100))% · reused cache · OK"
            )
            return
        }
        print(
            "Real bitmap subtitle · \(conversion.cueCount) cues · OCR \(Int(conversion.averageConfidence * 100))% · WebVTT timing and position · OK"
        )
        print(conversion.webVTT)
    }
}
