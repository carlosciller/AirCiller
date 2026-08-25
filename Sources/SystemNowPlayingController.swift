import AppKit
import Foundation
import MediaPlayer

@MainActor
final class SystemNowPlayingController {
    var onPlay: (() -> Void)?
    var onPause: (() -> Void)?
    var onToggle: (() -> Void)?
    var onStop: (() -> Void)?
    var onSeek: ((Double) -> Void)?
    var onSkip: ((Double) -> Void)?

    private let center = MPNowPlayingInfoCenter.default()
    private let commands = MPRemoteCommandCenter.shared()
    private var targets: [(MPRemoteCommand, Any)] = []
    private var publishedTitle = ""
    private var publishedDuration = 0.0
    private var publishedPosition = 0.0
    private var publishedPlaying = false
    private var publishedQueueIndex: Int?
    private var publishedQueueCount: Int?
    private var publishedAt = Date.distantPast
    private lazy var artwork: MPMediaItemArtwork? = {
        guard
            let url = Bundle.main.url(
                forResource: "AirCillerArtwork",
                withExtension: "png"
            ), let image = NSImage(contentsOf: url)
        else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }()

    init() {
        commands.playCommand.isEnabled = true
        addTarget(to: commands.playCommand) { [weak self] _ in
            self?.onPlay?()
        }

        commands.pauseCommand.isEnabled = true
        addTarget(to: commands.pauseCommand) { [weak self] _ in
            self?.onPause?()
        }

        commands.togglePlayPauseCommand.isEnabled = true
        addTarget(to: commands.togglePlayPauseCommand) { [weak self] _ in
            self?.onToggle?()
        }

        commands.stopCommand.isEnabled = true
        addTarget(to: commands.stopCommand) { [weak self] _ in
            self?.onStop?()
        }

        commands.changePlaybackPositionCommand.isEnabled = true
        addTarget(to: commands.changePlaybackPositionCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return }
            self?.onSeek?(event.positionTime)
        }

        commands.skipForwardCommand.isEnabled = true
        commands.skipForwardCommand.preferredIntervals = [10]
        addTarget(to: commands.skipForwardCommand) { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            self?.onSkip?(interval)
        }

        commands.skipBackwardCommand.isEnabled = true
        commands.skipBackwardCommand.preferredIntervals = [10]
        addTarget(to: commands.skipBackwardCommand) { [weak self] event in
            let interval = (event as? MPSkipIntervalCommandEvent)?.interval ?? 10
            self?.onSkip?(-interval)
        }
        setCommandsEnabled(false)
    }

    isolated deinit {
        for (command, target) in targets {
            command.removeTarget(target)
        }
    }

    func update(
        title: String,
        duration: Double,
        position: Double,
        playing: Bool,
        queueIndex: Int?,
        queueCount: Int?
    ) {
        guard duration.isFinite, duration > 0, position.isFinite else { return }
        let now = Date()
        let predictedPosition =
            publishedPlaying
            ? min(publishedDuration, publishedPosition + now.timeIntervalSince(publishedAt))
            : publishedPosition
        let timelineChanged = abs(position - predictedPosition) > 2
        let identityChanged =
            title != publishedTitle || abs(duration - publishedDuration) > 0.5
            || queueIndex != publishedQueueIndex || queueCount != publishedQueueCount
        guard identityChanged || timelineChanged || playing != publishedPlaying else { return }

        publishedTitle = title
        publishedDuration = duration
        publishedPosition = min(max(0, position), duration)
        publishedPlaying = playing
        publishedQueueIndex = queueIndex
        publishedQueueCount = queueCount
        publishedAt = now
        setCommandsEnabled(true)

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: publishedPosition,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyPlaybackProgress: publishedPosition / duration,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
            MPMediaItemPropertyMediaType: MPMediaType.movie.rawValue,
            MPNowPlayingInfoPropertyIsLiveStream: false,
            MPNowPlayingInfoPropertyExternalContentIdentifier: "local.carlosciller.AirCiller:\(title)",
        ]
        if #available(macOS 15.0, *) {
            info[MPNowPlayingInfoPropertyExcludeFromSuggestions] = true
        }
        if let queueIndex, let queueCount, queueIndex >= 0, queueCount > queueIndex {
            info[MPNowPlayingInfoPropertyPlaybackQueueIndex] = queueIndex
            info[MPNowPlayingInfoPropertyPlaybackQueueCount] = queueCount
        }
        if let artwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        center.nowPlayingInfo = info
        center.playbackState = playing ? .playing : .paused
    }

    func clear() {
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
        publishedTitle = ""
        publishedDuration = 0
        publishedPosition = 0
        publishedPlaying = false
        publishedQueueIndex = nil
        publishedQueueCount = nil
        publishedAt = .distantPast
        setCommandsEnabled(false)
    }

    private func addTarget(
        to command: MPRemoteCommand,
        handler: @escaping @MainActor (MPRemoteCommandEvent) -> Void
    ) {
        let target = command.addTarget { event in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { handler(event) }
            }
            return .success
        }
        targets.append((command, target))
    }

    private func setCommandsEnabled(_ enabled: Bool) {
        commands.playCommand.isEnabled = enabled
        commands.pauseCommand.isEnabled = enabled
        commands.togglePlayPauseCommand.isEnabled = enabled
        commands.stopCommand.isEnabled = enabled
        commands.changePlaybackPositionCommand.isEnabled = enabled
        commands.skipForwardCommand.isEnabled = enabled
        commands.skipBackwardCommand.isEnabled = enabled
    }
}
