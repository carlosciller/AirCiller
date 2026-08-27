import Foundation

@main
struct AttachedArtworkProbeSmokeTest {
    static func main() async throws {
        let testExecutable = ProcessInfo.processInfo.environment["AIRCILLER_TEST_FFMPEG"]
            .map(URL.init(fileURLWithPath:))
            .flatMap { FileManager.default.isExecutableFile(atPath: $0.path) ? $0 : nil }
        guard let ffmpegURL = testExecutable ?? Executables.find("ffmpeg") else {
            throw AirCillerError.ffmpegMissing
        }
        let ffprobeURL = ffmpegURL.deletingLastPathComponent().appendingPathComponent("ffprobe")
        guard FileManager.default.isExecutableFile(atPath: ffprobeURL.path) else {
            throw AirCillerError.ffprobeMissing
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-AttachedArtwork-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let artworkURL = root.appendingPathComponent("artwork.ppm")
        let videoFrameURL = root.appendingPathComponent("video.ppm")
        try ppm(width: 64, height: 64, red: 0, green: 0, blue: 255).write(to: artworkURL)
        try ppm(width: 320, height: 180, red: 255, green: 0, blue: 0).write(to: videoFrameURL)

        let mediaURL = root.appendingPathComponent("artwork-and-video.mp4")
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-hide_banner", "-loglevel", "error", "-y",
            "-loop", "1", "-i", artworkURL.path,
            "-loop", "1", "-i", videoFrameURL.path,
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

        let probe = try await MediaProbeService.probe(url: mediaURL, ffprobeURL: ffprobeURL)
        guard probe.videoCodec == "mpeg4", probe.width == 320, probe.height == 180 else {
            throw NSError(domain: "AttachedArtworkProbeSmokeTest.Selection", code: 2)
        }

        print("Attached artwork is excluded from primary video selection: OK")
    }

    private static func ppm(
        width: Int,
        height: Int,
        red: UInt8,
        green: UInt8,
        blue: UInt8
    ) -> Data {
        var data = Data("P6\n\(width) \(height)\n255\n".utf8)
        for _ in 0..<(width * height) {
            data.append(contentsOf: [red, green, blue])
        }
        return data
    }
}
