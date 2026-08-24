import Foundation

@main
struct PGSLargeCanvasSmokeTest {
    static func main() async throws {
        let inputPath =
            CommandLine.arguments.dropFirst().first
            ?? ProcessInfo.processInfo.environment["AIRCILLER_TEST_PGS_LARGE_MEDIA"]
        guard let inputPath, FileManager.default.fileExists(atPath: inputPath) else {
            throw NSError(
                domain: "PGSLargeCanvasSmokeTest.Input",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Provide a large-canvas PGS file as an argument or through AIRCILLER_TEST_PGS_LARGE_MEDIA."
                ]
            )
        }
        let input = URL(fileURLWithPath: inputPath)
        let probe = try await MediaProbeService.probe(url: input)
        guard let track = probe.subtitleTracks.first(where: \.usesBitmapOCR) else {
            throw NSError(domain: "PGSLargeCanvasSmokeTest.Track", code: 2)
        }
        let cache = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-PGS-Large-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: cache) }
        let conversion = try await PGSSubtitleConverter.convert(
            track: track,
            videoURL: input,
            videoDuration: probe.duration,
            maximumRenderedFrames: 8,
            cacheDirectory: cache
        )
        guard conversion.cueCount >= 1,
            conversion.webVTT.contains("line:"),
            conversion.webVTT.contains("position:"),
            conversion.averageConfidence >= 0.45
        else {
            throw NSError(
                domain: "PGSLargeCanvasSmokeTest.Output",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: conversion.webVTT]
            )
        }
        print(
            "PGS 4K/letterbox · lienzo 1920×1080 detectado · \(conversion.cueCount) cues · OCR \(Int(conversion.averageConfidence * 100)) % · OK"
        )
    }
}
