import Foundation

/// Opt-in media check. Arguments: source, new output directory, pinned FFmpeg bin directory.
@main
struct TransportStreamPackagingSmokeTest {
    static func main() async throws {
        let options = CommandLine.arguments
        let hdrHLS = options.count == 5 && options[4] == "--hdr-hls"
        guard options.count == 4 || hdrHLS else { throw Failure.invalidInput }
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let engine = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
        guard MediaFileTypes.accepts(input), !FileManager.default.fileExists(atPath: output.path) else {
            throw Failure.invalidInput
        }
        let probe = try await MediaProbeService.probe(url: input, ffprobeURL: engine.appendingPathComponent("ffprobe"))
        guard (45...180).contains(probe.duration), ["h264", "hevc"].contains(probe.videoCodec),
            let audio = probe.audioTracks.first, audio.canPassThrough
        else { throw Failure.invalidInput }
        guard !hdrHLS || probe.isHDR else { throw Failure.invalidInput }
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let arguments: [String]
        if probe.isHDR && !hdrHLS {
            let subtitleURL = output.appendingPathComponent("cue.srt")
            try "1\n00:00:00,000 --> 00:01:00,000\nTransport stream check\n".write(
                to: subtitleURL, atomically: true, encoding: .utf8)
            arguments = DirectFileCommandBuilder.arguments(
                input: input, output: output.appendingPathComponent("movie.mp4"), probe: probe,
                audio: audio, outputMode: .original, audioDelay: 0,
                subtitle: MediaProbeService.externalTrack(url: subtitleURL), subtitleDelay: 0)
        } else if hdrHLS {
            arguments = VODCommandBuilder.multiplexedArguments(
                input: input, outputDirectory: output, probe: probe, audio: audio,
                outputMode: .original, audioDelay: 0)
        } else {
            arguments = VODCommandBuilder.arguments(
                input: input, outputDirectory: output, probe: probe, audio: audio,
                outputMode: .original, audioDelay: 0)
        }
        for option in ["-c:v", "-c:a"] {
            guard let index = arguments.firstIndex(of: option), arguments[index + 1] == "copy" else {
                throw Failure.transcodingRequested
            }
        }
        let result = try await CapturedProcess.run(
            executable: engine.appendingPathComponent("ffmpeg"), arguments: arguments)
        guard result.status == 0 else {
            throw AirCillerError.ffmpegStopped(String(decoding: result.errorOutput, as: UTF8.self))
        }
        if probe.isHDR && !hdrHLS {
            let movie = output.appendingPathComponent("movie.mp4")
            if probe.colorTransfer == "smpte2084" {
                try HDRConfigurationInjector.injectStaticMetadataIntoDirectFile(movie)
            }
            let prepared = try await MediaProbeService.probe(
                url: movie, ffprobeURL: engine.appendingPathComponent("ffprobe"))
            guard prepared.isHDR, abs(prepared.duration - probe.duration) < 1,
                prepared.audioTracks.first?.codec == audio.codec, prepared.subtitleTracks.count == 1
            else { throw Failure.invalidOutput }
        } else {
            if hdrHLS {
                let initialization = output.appendingPathComponent("video-init.mp4")
                try HDRConfigurationInjector.normalizeHLSFileType(initializationSegment: initialization)
                if probe.colorTransfer == "smpte2084" {
                    try HDRConfigurationInjector.injectStaticMetadata(
                        initializationSegment: initialization,
                        firstMediaSegment: output.appendingPathComponent("video-00000000.m4s"))
                }
            }
            for name in hdrHLS ? ["video.m3u8"] : ["video.m3u8", "audio.m3u8"] {
                let playlist = try String(contentsOf: output.appendingPathComponent(name), encoding: .utf8)
                guard playlist.contains("#EXT-X-ENDLIST"), playlist.contains("#EXT-X-PLAYLIST-TYPE:VOD") else {
                    throw Failure.invalidOutput
                }
            }
        }
        let route = hdrHLS ? "HDR HLS without subtitles" : (probe.isHDR ? "direct HDR" : "HLS VOD")
        print("Copy-only \(probe.videoCodec)/\(audio.codec), \(probe.duration)s, \(route): OK")
    }

    private enum Failure: Error { case invalidInput, transcodingRequested, invalidOutput }
}
