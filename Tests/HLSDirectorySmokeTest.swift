import AVFoundation
import Foundation

@main
struct HLSDirectorySmokeTest {
    static func main() async throws {
        guard (2...4).contains(CommandLine.arguments.count) else {
            throw NSError(domain: "HLSDirectorySmokeTest.Usage", code: 2)
        }
        let directory = URL(
            fileURLWithPath: CommandLine.arguments[1],
            isDirectory: true
        )
        let server = LocalHTTPServer(rootDirectory: directory)
        let baseURL = try await server.start()
        defer { server.stop() }

        let playlistName =
            CommandLine.arguments.count >= 3
            ? CommandLine.arguments[2]
            : "master.m3u8"
        let asset = AVURLAsset(url: baseURL.appendingPathComponent(playlistName))
        guard try await asset.load(.isPlayable) else {
            throw NSError(domain: "HLSDirectorySmokeTest.NotPlayable", code: 3)
        }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw NSError(domain: "HLSDirectorySmokeTest.Duration", code: 4)
        }

        let item = AVPlayerItem(asset: asset)
        if CommandLine.arguments.count == 4,
            CommandLine.arguments[3] == "subtitles"
        {
            guard let group = try await asset.loadMediaSelectionGroup(for: .legible),
                let option = group.options.first
            else {
                throw NSError(domain: "HLSDirectorySmokeTest.Legible", code: 6)
            }
            item.select(option, in: group)
        }
        let player = AVPlayer(playerItem: item)
        player.play()
        let deadline = Date().addingTimeInterval(15)
        while item.status == .unknown, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard item.status == .readyToPlay, item.error == nil else {
            throw item.error ?? NSError(domain: "HLSDirectorySmokeTest.Player", code: 5)
        }
        try await Task.sleep(for: .milliseconds(700))
        guard item.error == nil else { throw item.error! }
        player.pause()
        print("HLS \(TimeFormatting.duration(duration)) · video and audio · OK")
    }
}
