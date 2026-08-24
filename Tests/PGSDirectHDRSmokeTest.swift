import AVFoundation
import Foundation

@main
struct PGSDirectHDRSmokeTest {
    static func main() async throws {
        let paths = Array(CommandLine.arguments.dropFirst())
        let environment = ProcessInfo.processInfo.environment
        let pgsPath = paths.first ?? environment["AIRCILLER_TEST_PGS_MEDIA"]
        let hdrPath = paths.dropFirst().first ?? environment["AIRCILLER_TEST_HDR_MEDIA"]
        guard let pgsPath, let hdrPath,
            FileManager.default.fileExists(atPath: pgsPath),
            FileManager.default.fileExists(atPath: hdrPath)
        else {
            throw NSError(
                domain: "PGSDirectHDRSmokeTest.Input",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Provide a file containing PGS followed by an HDR/Dolby Vision file."
                ]
            )
        }
        let pgsInput = URL(fileURLWithPath: pgsPath)
        let hdrInput = URL(fileURLWithPath: hdrPath)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-PGS-HDR-Test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pgsProbe = try await MediaProbeService.probe(url: pgsInput)
        guard let pgsTrack = pgsProbe.subtitleTracks.first(where: \.usesBitmapOCR) else {
            throw NSError(domain: "PGSDirectHDRSmokeTest.PGSTrack", code: 2)
        }
        let textTrack = try await SubtitleService.materializeDirectTrack(
            pgsTrack,
            videoURL: pgsInput,
            videoDuration: pgsProbe.duration,
            outputDirectory: directory,
            maximumOCRFrames: 8
        )
        guard textTrack.codec == "webvtt", textTrack.externalPath != nil else {
            throw NSError(domain: "PGSDirectHDRSmokeTest.Materialization", code: 3)
        }

        let probe = try await MediaProbeService.probe(url: hdrInput)
        guard let audio = probe.audioTracks.first,
            let ffmpeg = Executables.find("ffmpeg")
        else {
            throw NSError(domain: "PGSDirectHDRSmokeTest.HDRTrack", code: 4)
        }
        let output = directory.appendingPathComponent("movie.mp4")
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = DirectFileCommandBuilder.arguments(
            input: hdrInput,
            output: output,
            probe: probe,
            audio: audio,
            outputMode: .original,
            audioDelay: 0,
            subtitle: textTrack,
            subtitleDelay: 0,
            durationLimit: 120
        )
        let errors = Pipe()
        let errorBuffer = ProcessDataBuffer(maximumBytes: 128_000)
        errors.fileHandleForReading.readabilityHandler = { errorBuffer.append($0.availableData) }
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        try? errors.fileHandleForWriting.close()
        process.waitUntilExit()
        errors.fileHandleForReading.readabilityHandler = nil
        errorBuffer.append(errors.fileHandleForReading.readDataToEndOfFile())
        guard process.terminationStatus == 0 else {
            throw AirCillerError.ffmpegStopped(
                String(data: errorBuffer.snapshot, encoding: .utf8) ?? ""
            )
        }

        let prepared = try await MediaProbeService.probe(url: output)
        let asset = AVURLAsset(url: output)
        guard prepared.isDolbyVision,
            !prepared.audioTracks.isEmpty,
            !prepared.subtitleTracks.isEmpty,
            abs(prepared.duration - 120) < 2,
            try await asset.load(.isPlayable),
            let legible = try await asset.loadMediaSelectionGroup(for: .legible),
            !legible.options.isEmpty
        else {
            throw NSError(domain: "PGSDirectHDRSmokeTest.Output", code: 5)
        }
        print("Real PGS → local OCR → Dolby Vision MP4 with selectable subtitles · OK")
    }
}
