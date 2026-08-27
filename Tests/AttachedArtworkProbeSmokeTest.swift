import Foundation

@main
struct AttachedArtworkProbeSmokeTest {
    static func main() async throws {
        guard let ffmpegURL = Executables.find("ffmpeg") else {
            throw AirCillerError.ffmpegMissing
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-AttachedArtwork-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let mediaURL = root.appendingPathComponent("artwork-and-video.mp4")
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-hide_banner", "-loglevel", "error", "-y",
            "-f", "lavfi", "-i", "color=c=blue:s=64x64",
            "-f", "lavfi", "-i", "color=c=red:s=320x180:d=1",
            "-map", "0:v", "-map", "1:v",
            "-c:v:0", "mjpeg", "-frames:v:0", "1", "-disposition:v:0", "attached_pic",
            "-c:v:1", "mpeg4", "-t", "1",
            mediaURL.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "AttachedArtworkProbeSmokeTest.Fixture", code: 1)
        }

        let probe = try await MediaProbeService.probe(url: mediaURL)
        guard probe.videoCodec == "mpeg4", probe.width == 320, probe.height == 180 else {
            throw NSError(domain: "AttachedArtworkProbeSmokeTest.Selection", code: 2)
        }

        print("Attached artwork is excluded from primary video selection: OK")
    }
}
