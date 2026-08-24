import AVFoundation
import Foundation

@main
struct VODPlaybackSmokeTest {
    static func main() async throws {
        guard CommandLine.arguments.count >= 5,
            let audioIndex = Int(CommandLine.arguments[3])
        else {
            throw NSError(domain: "VODPlaybackSmokeTest.Usage", code: 2)
        }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let durationLimit = ProcessInfo.processInfo.environment["AIRCILLER_TEST_LIMIT"].flatMap(Double.init)
        let outputMode =
            ProcessInfo.processInfo.environment["AIRCILLER_TEST_AUDIO_MODE"]
            .flatMap(AudioOutputMode.init(rawValue:)) ?? .original
        let audioDelay = ProcessInfo.processInfo.environment["AIRCILLER_TEST_AUDIO_DELAY"].flatMap(Double.init) ?? 0
        let multiplexed = ProcessInfo.processInfo.environment["AIRCILLER_TEST_MULTIPLEXED"] == "1"
        let subtitleArguments = Array(CommandLine.arguments.dropFirst(4))

        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        mark("probing")
        let probe = try await MediaProbeService.probe(url: input)
        guard let audio = probe.audioTracks.first(where: { $0.streamIndex == audioIndex }) else {
            throw NSError(domain: "VODPlaybackSmokeTest.Audio", code: 4)
        }
        if FileManager.default.fileExists(atPath: output.appendingPathComponent("video.m3u8").path) {
            mark("reusing existing VOD")
        } else {
            mark("packaging VOD")
            try packageVOD(
                input: input,
                output: output,
                probe: probe,
                audio: audio,
                outputMode: outputMode,
                audioDelay: audioDelay,
                multiplexed: multiplexed,
                durationLimit: durationLimit
            )
            mark("VOD complete")
        }
        try SubtitleService.alignRenditionPlaylists(
            outputDirectory: output,
            expectedDuration: min(probe.duration, durationLimit ?? probe.duration)
        )

        let server = LocalHTTPServer(rootDirectory: output)
        let baseURL = try await server.start()
        defer { server.stop() }

        for subtitleArgument in subtitleArguments {
            let subtitle: SubtitleTrack?
            if subtitleArgument == "none" {
                subtitle = nil
            } else if let subtitleIndex = Int(subtitleArgument) {
                guard let detected = probe.subtitleTracks.first(where: { $0.streamIndex == subtitleIndex }) else {
                    throw NSError(domain: "VODPlaybackSmokeTest.Subtitle", code: 5)
                }
                subtitle = detected
            } else {
                subtitle = MediaProbeService.externalTrack(url: URL(fileURLWithPath: subtitleArgument))
            }
            if let subtitle {
                mark("preparing subtitle \(subtitleArgument)")
                try await SubtitleService.prepare(
                    track: subtitle,
                    videoURL: input,
                    delay: 0,
                    videoPlaylistURL: output.appendingPathComponent("video.m3u8"),
                    outputDirectory: output
                )
                try SubtitleService.alignRenditionPlaylists(
                    outputDirectory: output,
                    expectedDuration: min(probe.duration, durationLimit ?? probe.duration)
                )
            } else {
                mark("testing without subtitles")
            }
            try SubtitleService.writeMasterPlaylist(
                probe: probe,
                audio: audio,
                audioOutputMode: outputMode,
                subtitle: subtitle,
                outputDirectory: output
            )
            let expectedDuration = min(probe.duration, durationLimit ?? probe.duration)
            let packagedDuration = try SubtitleService.validatePackage(
                outputDirectory: output,
                expectedDuration: expectedDuration,
                hasAudio: !multiplexed,
                hasSubtitles: subtitle != nil
            )

            var components = URLComponents(
                url: baseURL.appendingPathComponent("master.m3u8"),
                resolvingAgainstBaseURL: false
            )!
            components.queryItems = [URLQueryItem(name: "track", value: subtitleArgument)]
            let asset = AVURLAsset(url: components.url!)
            mark("AVPlayer isPlayable \(subtitleArgument)")
            guard try await asset.load(.isPlayable) else {
                throw NSError(domain: "VODPlaybackSmokeTest.NotPlayable", code: 6)
            }
            mark("AVPlayer duration \(subtitleArgument)")
            let loadedDuration = try await asset.load(.duration).seconds
            guard loadedDuration.isFinite,
                abs(loadedDuration - packagedDuration) <= max(2.5, expectedDuration * 0.002)
            else {
                throw NSError(domain: "VODPlaybackSmokeTest.Duration", code: 7)
            }
            let item = AVPlayerItem(asset: asset)
            if subtitle != nil {
                mark("AVPlayer legible group \(subtitleArgument)")
                guard let group = try await asset.loadMediaSelectionGroup(for: .legible),
                    let option = group.options.first
                else {
                    throw NSError(domain: "VODPlaybackSmokeTest.Legible", code: 8)
                }
                item.select(option, in: group)
            }
            let player = AVPlayer(playerItem: item)
            player.play()
            mark("AVPlayer playback \(subtitleArgument)")
            let deadline = Date().addingTimeInterval(15)
            while item.status == .unknown, Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            guard item.status == .readyToPlay, item.error == nil else {
                throw item.error ?? NSError(domain: "VODPlaybackSmokeTest.PlayerItem", code: 9)
            }
            try await Task.sleep(for: .milliseconds(700))
            guard item.error == nil else { throw item.error! }
            player.pause()

            let trackDescription =
                subtitle.map {
                    "track \(subtitleArgument) · \($0.displayName) · "
                } ?? "without subtitles · "
            print(
                trackDescription + "VOD \(TimeFormatting.duration(loadedDuration)) · "
                    + (subtitle == nil ? "video and audio · OK" : "selectable WebVTT · OK")
            )
        }
    }

    private static func mark(_ text: String) {
        FileHandle.standardError.write(Data(("[VOD test] \(text)\n").utf8))
    }

    private static func packageVOD(
        input: URL,
        output: URL,
        probe: MediaProbe,
        audio: AudioTrack,
        outputMode: AudioOutputMode,
        audioDelay: Double,
        multiplexed: Bool,
        durationLimit: Double?
    ) throws {
        guard let ffmpeg = Executables.find("ffmpeg") else {
            throw AirCillerError.ffmpegMissing
        }
        let process = Process()
        process.executableURL = ffmpeg
        process.arguments =
            multiplexed
            ? VODCommandBuilder.multiplexedArguments(
                input: input,
                outputDirectory: output,
                probe: probe,
                audio: audio,
                outputMode: outputMode,
                audioDelay: audioDelay,
                durationLimit: durationLimit
            )
            : VODCommandBuilder.arguments(
                input: input,
                outputDirectory: output,
                probe: probe,
                audio: audio,
                outputMode: outputMode,
                audioDelay: audioDelay,
                durationLimit: durationLimit
            )
        let errors = Pipe()
        let errorBuffer = ProcessDataBuffer(maximumBytes: 64_000)
        errors.fileHandleForReading.readabilityHandler = { handle in
            errorBuffer.append(handle.availableData)
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = errors
        try process.run()
        try? errors.fileHandleForWriting.close()
        process.waitUntilExit()
        errors.fileHandleForReading.readabilityHandler = nil
        errorBuffer.append(errors.fileHandleForReading.readDataToEndOfFile())
        guard process.terminationStatus == 0 else {
            let data = errorBuffer.snapshot
            throw AirCillerError.ffmpegStopped(String(data: data, encoding: .utf8) ?? "")
        }
    }
}
