import AVFoundation
import Foundation

@main
struct DirectMP4SmokeTest {
    static func main() async throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "DirectMP4SmokeTest.Usage", code: 2)
        }
        let fileURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let server = LocalHTTPServer(rootDirectory: fileURL.deletingLastPathComponent())
        let baseURL = try await server.start()
        defer { server.stop() }
        let asset = AVURLAsset(url: baseURL.appendingPathComponent(fileURL.lastPathComponent))
        guard try await asset.load(.isPlayable) else {
            throw NSError(domain: "DirectMP4SmokeTest.NotPlayable", code: 3)
        }
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else {
            throw NSError(domain: "DirectMP4SmokeTest.Duration", code: 4)
        }
        guard let audio = try await asset.loadMediaSelectionGroup(for: .audible),
            !audio.options.isEmpty
        else {
            throw NSError(domain: "DirectMP4SmokeTest.Audio", code: 5)
        }
        guard let subtitles = try await asset.loadMediaSelectionGroup(for: .legible),
            let subtitle = subtitles.options.first
        else {
            throw NSError(domain: "DirectMP4SmokeTest.Subtitles", code: 6)
        }

        let item = AVPlayerItem(asset: asset)
        item.select(subtitle, in: subtitles)
        let player = AVPlayer(playerItem: item)
        player.play()
        let deadline = Date().addingTimeInterval(10)
        while item.status == .unknown, Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard item.status == .readyToPlay, item.error == nil else {
            throw item.error ?? NSError(domain: "DirectMP4SmokeTest.Player", code: 7)
        }
        try await Task.sleep(for: .milliseconds(700))
        guard item.error == nil else { throw item.error! }
        player.pause()
        print("Direct HTTP MP4 · video + audio + selectable subtitles · \(TimeFormatting.duration(duration)) · OK")
    }
}
