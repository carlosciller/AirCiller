import AppKit
import AVFoundation
import AetherEngine
import Foundation

// Research host only. No Keychain, receiver discovery, capture or preferences.
@main
struct AetherComparisonHost {
    static func main() {
        Task { @MainActor in
            let result = await run()
            exit(result)
        }
        CFRunLoopRun()
    }

    @MainActor static func run() async -> Int32 {
        let args = CommandLine.arguments
        guard args.count == 4 else { return 2 }
        let input = URL(fileURLWithPath: args[1])
        let report = URL(fileURLWithPath: args[2])
        let stop = args[3]
        let began = ProcessInfo.processInfo.systemUptime
        EngineLog.handler = { message in
            FileHandle.standardError.write(Data((message + "\n").utf8))
        }
        var result: [String: Any] = ["status": "starting"]
        var engine: AetherEngine?
        func save() throws {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: report, options: .atomic)
        }
        defer { engine?.stop() }
        do {
            let probe = try AetherEngine.probe(url: input)
            guard ["h264", "hevc"].contains(probe.videoCodecName ?? ""),
                  probe.audioTracks.count == 1,
                  ["aac", "ac3", "eac3", "alac"].contains(probe.audioTracks[0].codec.lowercased()),
                  probe.durationSeconds > 0, probe.durationSeconds <= 120,
                  probe.dvProfile == nil || probe.dvProfile == 5 || probe.dvProfile == 8 else {
                result["status"] = "refused-input-outside-original-stream-fixtures"
                try save()
                return 3
            }
            let player = try AetherEngine()
            engine = player
            player.volume = 0
            let options = LoadOptions(
                suppressDisplayCriteria: true,
                panelIsInHDRMode: true,
                panelPresentsDolbyVision: probe.isDolbyVision,
                prepareNativeSubtitles: true,
                eagerNativeSubtitleReaders: true,
                generatesBackgroundScrubPreviews: false,
                forwardBufferSegments: 64,
                sessionCacheByteBudget: 256 * 1024 * 1024,
                autoplay: false,
                escalatesToSoftwarePath: false)
            try await player.load(url: input, options: options)
            guard player.audioDelivery == .streamCopy,
                  let asset = player.currentAVPlayer?.currentItem?.asset as? AVURLAsset,
                  asset.url.host == "127.0.0.1" else {
                result["status"] = "not-original-native-loopback"
                result["audioDelivery"] = String(describing: player.audioDelivery)
                result["route"] = String(describing: player.videoRoute)
                result["assetType"] = String(describing: player.currentAVPlayer?.currentItem?.asset)
                try save()
                return 4
            }
            if !player.nativeSubtitleTracks.isEmpty {
                player.setNativeSubtitleSelected(track: 0)
                player.setNativeSubtitleRendering(true)
            }
            result = [
                "status": "local-session-ready",
                "url": asset.url.absoluteString,
                "loadSeconds": ProcessInfo.processInfo.systemUptime - began,
                "duration": player.duration,
                "audioDelivery": String(describing: player.audioDelivery),
                "route": String(describing: player.videoRoute),
                "nativeSubtitleTracks": player.nativeSubtitleTracks.count,
                "sourceSubtitles": probe.subtitleTracks.count,
                "videoCodec": probe.videoCodecName ?? "",
                "audioCodec": probe.audioTracks[0].codec
            ]
            try save()
            let deadline = ProcessInfo.processInfo.systemUptime + 120
            while !FileManager.default.fileExists(atPath: stop),
                  ProcessInfo.processInfo.systemUptime < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            player.stop()
            result["stopped"] = true
            try save()
            return 0
        } catch {
            result["status"] = "failed"
            result["error"] = String(describing: error)
            try? save()
            return 1
        }
    }
}
