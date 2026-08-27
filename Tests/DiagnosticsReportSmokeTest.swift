import Foundation

@main
struct DiagnosticsReportSmokeTest {
    static func main() throws {
        let privatePath = "/" + ["Users", "placeholder", "My Movie", "private"].joined(separator: "/")
        let volumePath = "/" + ["Volumes", "External", "Secret Movie"].joined(separator: "/")
        let privateAddress = ["192", "168", "1", "33"].joined(separator: ".")
        let snapshot = DiagnosticsReportSnapshot(
            appVersion: "0.10.3",
            appBuild: "43",
            systemVersion: "macOS 27.0",
            architecture: "arm64",
            appLanguage: "en",
            playbackState: "playing",
            playbackRoute: "HLS/fMP4 VOD",
            currentTime: 90,
            duration: 7_200,
            rebufferEvents: 1,
            networkReady: true,
            videoCodec: "hevc",
            videoDimensions: "3840x2160",
            dolbyVisionProfile: 8,
            hdr: true,
            audioCodec: "eac3",
            audioMode: "original",
            subtitleCodec: "webvtt",
            subtitleKind: "standard",
            receiverModel: "AppleTV14,1",
            receiverSystem: "tvOS 26.6",
            receiverProtocol: "AirPlay 2",
            authorizationState: "authorized",
            ffmpegVersion: "9.0.1",
            ffmpegSource: "Homebrew \(privatePath)",
            airPlayVersion: "3.13.7 token=abc123, source \(volumePath)",
            airPlaySource: privateAddress
        )
        let report = DiagnosticsReport.render(
            snapshot,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
        let required = [
            "AirCiller: 0.10.3 (43)",
            "Playback route: HLS/fMP4 VOD",
            "[path removed]",
            "[secret removed]",
            "[address removed]",
        ]
        for (index, value) in required.enumerated() where !report.contains(value) {
            throw NSError(domain: "DiagnosticsReportSmokeTest.MissingRedaction", code: index + 1)
        }
        let forbidden = [privatePath, volumePath, "Secret Movie", "abc123", privateAddress]
        for (index, value) in forbidden.enumerated() where report.contains(value) {
            throw NSError(domain: "DiagnosticsReportSmokeTest.LeakedValue", code: index + 1)
        }
        print("Local diagnostics are useful and exclude personal paths, addresses, and credentials: OK")
    }
}
