import AVFoundation
import CoreVideo
import Foundation

/// Muted, receiver-free playback of a synthetic HTTP HLS package.
@main
struct HLSLocalPlayerProbe {
    @MainActor
    static func main() async throws {
        guard CommandLine.arguments.count == 2,
            let url = URL(string: CommandLine.arguments[1]), url.host == "127.0.0.1"
        else { throw Failure.invalidInput }
        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        let deadline = Date().addingTimeInterval(20)
        while item.status == .unknown && Date() < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard item.status == .readyToPlay else {
            print("status=\(item.status.rawValue), error=\(String(describing: item.error))")
            throw Failure.notReady
        }
        print("duration=\(item.duration.seconds), ranges=\(item.seekableTimeRanges)")
        player.play()
        let started = Date()
        var frames = 0
        while Date().timeIntervalSince(started) < 8 {
            let time = player.currentTime()
            if output.hasNewPixelBuffer(forItemTime: time) {
                var displayed = CMTime.invalid
                if output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: &displayed) != nil {
                    frames += 1
                    if frames <= 3 { print("frame itemTime=\(time.seconds) displayed=\(displayed.seconds)") }
                }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        print("frames=\(frames), finalTime=\(player.currentTime().seconds), status=\(item.status.rawValue)")
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 10 else { throw Failure.invalidDuration }
        player.pause()
        let target = CMTime(seconds: duration - 3, preferredTimescale: 600)
        let sought = await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        guard sought else { throw Failure.seekFailed }
        player.play()
        let endDeadline = Date().addingTimeInterval(12)
        while Date() < endDeadline {
            guard item.status == .readyToPlay else { throw Failure.notReady }
            if player.rate == 0 && player.currentTime().seconds >= duration - 0.1 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let finalTime = player.currentTime().seconds
        let ended = player.rate == 0
        print("tailTime=\(finalTime), expectedEnd=\(duration), rate=\(player.rate)")
        player.pause()
        player.replaceCurrentItem(with: nil)
        guard frames > 0 else { throw Failure.noFrames }
        guard ended, finalTime >= duration - 0.1 else { throw Failure.truncatedTail }
    }

    private enum Failure: Error {
        case invalidInput, notReady, noFrames, invalidDuration, seekFailed, truncatedTail
    }
}
