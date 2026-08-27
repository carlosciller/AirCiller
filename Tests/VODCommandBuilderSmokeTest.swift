import Foundation

@main
struct VODCommandBuilderSmokeTest {
    static func main() throws {
        let probe = MediaProbe(
            duration: 7_200,
            fileSize: 42_000_000_000,
            bitRate: 46_000_000,
            videoStreamIndex: 5,
            videoCodec: "hevc",
            videoProfile: "Main 10",
            videoLevel: 153,
            hevcCodecIdentifier: nil,
            width: 3_840,
            height: 2_160,
            frameRate: "24000/1001",
            colorTransfer: "smpte2084",
            isDolbyVision: true,
            dolbyVisionProfile: 8,
            dolbyVisionLevel: 6,
            dolbyVisionCompatibilityID: 1,
            audioTracks: [],
            subtitleTracks: [],
            chapters: []
        )
        let input = URL(fileURLWithPath: "/tmp/feature.mkv")
        let directory = URL(fileURLWithPath: "/tmp/vod")

        let separate = VODCommandBuilder.arguments(
            input: input,
            outputDirectory: directory,
            probe: probe,
            audio: nil,
            outputMode: .original,
            audioDelay: 0
        )
        let multiplexed = VODCommandBuilder.multiplexedArguments(
            input: input,
            outputDirectory: directory,
            probe: probe,
            audio: nil,
            outputMode: .original,
            audioDelay: 0
        )
        let direct = DirectFileCommandBuilder.arguments(
            input: input,
            output: directory.appendingPathComponent("feature.mp4"),
            probe: probe,
            audio: nil,
            outputMode: .original,
            audioDelay: 0,
            subtitle: nil,
            subtitleDelay: 0
        )

        for arguments in [separate, multiplexed, direct] {
            guard containsMap("0:5", in: arguments), !arguments.contains("0:v:0") else {
                throw NSError(domain: "VODCommandBuilderSmokeTest.VideoMap", code: 1)
            }
        }
        print("Exact primary video stream mapping for HLS and direct MP4: OK")
    }

    private static func containsMap(_ value: String, in arguments: [String]) -> Bool {
        arguments.indices.contains { index in
            arguments[index] == "-map"
                && arguments.index(after: index) < arguments.endIndex
                && arguments[arguments.index(after: index)] == value
        }
    }
}
