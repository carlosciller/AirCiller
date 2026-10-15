import Foundation

/// Opt-in command generation for the fixed synthetic H.264/E-AC-3 timing fixture.
@main
struct HLSAudioTimingCommandProbe {
    static func main() throws {
        guard [4, 5, 6].contains(CommandLine.arguments.count),
            let delay = Double(CommandLine.arguments[3]), delay.isFinite, abs(delay) <= 5
        else { throw Failure.invalidArguments }
        let audio = AudioTrack(
            streamIndex: 1, codec: "eac3", profile: nil, channels: 2, channelLayout: "stereo",
            language: nil, title: nil, isDefault: true)
        let probe = MediaProbe(
            duration: 60, fileSize: 0, bitRate: 0, videoStreamIndex: 0, videoCodec: "h264",
            videoProfile: "High", videoLevel: nil, hevcCodecIdentifier: nil,
            width: 1280, height: 720, frameRate: "24/1", colorTransfer: nil,
            isDolbyVision: false, dolbyVisionProfile: nil, dolbyVisionLevel: nil,
            dolbyVisionCompatibilityID: nil, audioTracks: [audio], subtitleTracks: [], chapters: [])
        var arguments = VODCommandBuilder.arguments(
            input: URL(fileURLWithPath: CommandLine.arguments[1]),
            outputDirectory: URL(fileURLWithPath: CommandLine.arguments[2]),
            probe: probe, audio: audio, outputMode: .original, audioDelay: delay)
        if CommandLine.arguments.count >= 5 {
            guard CommandLine.arguments[4] == "--shared-clock" else { throw Failure.invalidArguments }
            arguments.insert(contentsOf: ["-copyts", "-start_at_zero"], at: 0)
            if let offset = arguments.firstIndex(of: "-itsoffset") {
                arguments.insert(contentsOf: ["-isync", "0"], at: offset)
            }
            for index in arguments.indices.reversed() where arguments[index] == "-avoid_negative_ts" {
                arguments[index + 1] = "disabled"
                arguments.insert(
                    contentsOf: [
                        "-output_ts_offset", "10", "-hls_segment_options",
                        "movflags=+frag_discont:use_editlist=0:avoid_negative_ts=disabled",
                    ], at: index)
            }
            if CommandLine.arguments.count == 6 {
                guard CommandLine.arguments[5] == "--hold-first-frame", delay < 0,
                    let output = arguments.firstIndex(of: "-avoid_negative_ts")
                else { throw Failure.invalidArguments }
                let padding = String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), -delay)
                arguments.insert(
                    contentsOf: [
                        "-bsf:v",
                        "setts=pts=PTS-if(eq(N\\,0)\\,\(padding)/TB\\,0):dts=DTS-if(eq(N\\,0)\\,\(padding)/TB\\,0):duration=DURATION+if(eq(N\\,0)\\,\(padding)/TB\\,0)",
                    ],
                    at: output)
            }
        }
        let encoded = try JSONEncoder().encode(arguments)
        FileHandle.standardOutput.write(encoded)
    }

    private enum Failure: Error { case invalidArguments }
}
