import AVFoundation
import Foundation

@main
struct DirectFilePackagingSmokeTest {
    static func main() async throws {
        guard CommandLine.arguments.count == 5,
            let audioIndex = Int(CommandLine.arguments[3]),
            let subtitleIndex = Int(CommandLine.arguments[4])
        else {
            throw NSError(domain: "DirectFilePackagingSmokeTest.Usage", code: 2)
        }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])
        let probe = try await MediaProbeService.probe(url: input)
        guard let audio = probe.audioTracks.first(where: { $0.streamIndex == audioIndex }),
            let subtitle = probe.subtitleTracks.first(where: { $0.streamIndex == subtitleIndex })
        else {
            throw NSError(domain: "DirectFilePackagingSmokeTest.Tracks", code: 3)
        }
        guard let ffmpeg = Executables.find("ffmpeg") else { throw AirCillerError.ffmpegMissing }
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = DirectFileCommandBuilder.arguments(
            input: input,
            output: output,
            probe: probe,
            audio: audio,
            outputMode: .original,
            audioDelay: 0,
            subtitle: subtitle,
            subtitleDelay: 0,
            durationLimit: 60
        )
        let errors = Pipe()
        let errorBuffer = ProcessDataBuffer(maximumBytes: 64_000)
        errors.fileHandleForReading.readabilityHandler = { errorBuffer.append($0.availableData) }
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        try? errors.fileHandleForWriting.close()
        process.waitUntilExit()
        errors.fileHandleForReading.readabilityHandler = nil
        errorBuffer.append(errors.fileHandleForReading.readDataToEndOfFile())
        guard process.terminationStatus == 0 else {
            throw AirCillerError.ffmpegStopped(String(data: errorBuffer.snapshot, encoding: .utf8) ?? "")
        }

        let prepared = try await MediaProbeService.probe(url: output)
        guard prepared.isDolbyVision,
            !prepared.audioTracks.isEmpty,
            !prepared.subtitleTracks.isEmpty,
            abs(prepared.duration - 60) < 2
        else {
            throw NSError(domain: "DirectFilePackagingSmokeTest.Output", code: 4)
        }
        let asset = AVURLAsset(url: output)
        guard try await asset.load(.isPlayable),
            let legible = try await asset.loadMediaSelectionGroup(for: .legible),
            !legible.options.isEmpty
        else {
            throw NSError(domain: "DirectFilePackagingSmokeTest.AVPlayer", code: 5)
        }
        print("Dolby Vision directo · audio intacto · subtítulo seleccionable · OK")
    }
}
