import Foundation

/// App-local dispatcher. Only an authenticated, explicitly enabled transport
/// may expose it; this object itself opens no listener and launches no helper.
@MainActor
final class RemotePlaybackControl {
    struct Snapshot: Codable, Sendable {
        let sessionID: UUID
        let phase: String
        let title: String?
        let audioOffset: Double
        let subtitleOffset: Double
        let preparationProgress: Double?
        let position: Double?
        let duration: Double?
        let awaitingConversion: Bool
        let conversionDecisionID: UUID?
        let conversionOutput: String?
        let receiverObservedAt: Double?
    }

    struct Track: Codable, Sendable {
        let id: String
        let kind: String
        let language: String?
        let title: String?
        let codec: String
        let selected: Bool
    }

    struct Receiver: Codable, Sendable {
        let id: UUID
        let name: String
        let selected: Bool
    }

    struct Preferences: Codable, Sendable {
        let audio: String
        let subtitles: String
        let savedAudio: String
        let savedSubtitles: String
    }

    func receivers() -> [Receiver] {
        coordinator.airPlay.remotelyConfiguredDevices.map {
            Receiver(
                id: library.identifier(namespace: "receiver", localID: $0.id), name: $0.name,
                selected: $0.id == coordinator.airPlay.selectedDeviceID)
        }
    }

    func preferences() -> Preferences {
        Preferences(
            audio: coordinator.effectiveAudioLanguage, subtitles: coordinator.effectiveSubtitleLanguage,
            savedAudio: coordinator.preferredAudioLanguage, savedSubtitles: coordinator.preferredSubtitleLanguage)
    }

    enum Failure: Error, Equatable {
        case staleSession
        case unavailable
        case unsupportedCommand
        case missingItem
        case noNextItem
        case missingTrack
        case staleDecision
    }

    private let coordinator: StreamCoordinator
    private let library: RemoteLibraryIndex

    init(coordinator: StreamCoordinator, installationKey: Data) {
        self.coordinator = coordinator
        library = RemoteLibraryIndex(key: installationKey)
    }

    func search(_ query: String) throws -> [RemoteLibraryIndex.Item] {
        _ = try RemoteCommand.search(query: query).validatedEncoding()
        return library.search(query, queue: coordinator.queueItems, seasons: coordinator.seasonFolders)
    }

    private func trackID(_ id: String) -> String {
        library.identifier(namespace: "track:" + coordinator.remoteControlSessionID.uuidString, localID: id).uuidString
    }

    func tracks() -> [Track] {
        coordinator.audioTracks.map {
            Track(
                id: trackID($0.id), kind: "audio", language: $0.language, title: $0.title,
                codec: $0.codec, selected: $0.id == coordinator.selectedAudioID)
        }
            + coordinator.subtitleTracks.map {
                Track(
                    id: trackID($0.id), kind: "subtitle", language: $0.language, title: $0.title,
                    codec: $0.codec, selected: $0.id == coordinator.selectedSubtitleID)
            }
    }

    func snapshot() -> Snapshot {
        let phase: String
        if coordinator.hasError {
            phase = "error"
        } else if coordinator.showConversionAlert {
            phase = "awaiting_conversion"
        } else if coordinator.isAnalyzing {
            phase = "analyzing"
        } else if coordinator.isPreparing || coordinator.isWaitingToStart {
            phase = "preparing"
        } else if coordinator.isStreaming {
            if let observation = coordinator.remoteReceiverObservation, Date().timeIntervalSince(observation.at) <= 15 {
                phase = observation.playing ? "playing" : "paused"
            } else {
                phase = "awaiting_receiver_state"
            }
        } else {
            phase = "idle"
        }
        return Snapshot(
            sessionID: coordinator.remoteControlSessionID, phase: phase,
            title: coordinator.selectedURL?.lastPathComponent,
            audioOffset: coordinator.audioDelay, subtitleOffset: coordinator.subtitleDelay,
            preparationProgress: coordinator.isPreparing && coordinator.preparationProgress.isFinite
                ? min(1, max(0, coordinator.preparationProgress)) : nil,
            position: coordinator.remoteReceiverObservation?.position,
            duration: coordinator.remoteReceiverObservation?.duration
                ?? (coordinator.duration.isFinite ? coordinator.duration : 0),
            awaitingConversion: coordinator.showConversionAlert,
            conversionDecisionID: coordinator.remoteConversionDecisionID,
            conversionOutput: coordinator.showConversionAlert ? "lossy_eac3_up_to_5_1" : nil,
            receiverObservedAt: coordinator.remoteReceiverObservation?.at.timeIntervalSince1970)
    }

    /// Returns dispatch acceptance, never audiovisual confirmation. Relative
    /// commands require the transport's ledger admission before this call.
    func dispatch(_ command: RemoteCommand, sessionID: UUID) throws {
        _ = try command.validatedEncoding()
        guard sessionID == coordinator.remoteControlSessionID else { throw Failure.staleSession }
        switch command {
        case .setLanguages(let audio, let subtitles, let persistent):
            coordinator.setRemoteLanguagePreferences(audio: audio, subtitles: subtitles, persistent: persistent)
        case .selectReceiver(let id):
            guard !coordinator.isPreparing, !coordinator.isAnalyzing, !coordinator.isWaitingToStart,
                !coordinator.isStreaming,
                let device = coordinator.airPlay.remotelyConfiguredDevices.first(where: {
                    library.identifier(namespace: "receiver", localID: $0.id) == id
                }), coordinator.airPlay.selectConfiguredDeviceForRemote(device.id)
            else { throw Failure.unavailable }
        case .resolveConversion(let decisionID, let approve, let equivalentEpisodes):
            guard
                coordinator.resolveRemoteConversion(
                    decisionID: decisionID, approve: approve,
                    equivalentEpisodes: equivalentEpisodes)
            else { throw Failure.staleDecision }
        case .selectTracks(let audioID, let subtitleID):
            guard coordinator.commandAvailability.canEditTracks else { throw Failure.unavailable }
            // Nil audio preserves its current selection; nil subtitle means Off.
            let audio = audioID.flatMap { requested in coordinator.audioTracks.first { trackID($0.id) == requested } }
            let subtitle = subtitleID.flatMap { requested in
                coordinator.subtitleTracks.first { trackID($0.id) == requested }
            }
            guard audioID == nil || audio != nil, subtitleID == nil || subtitle != nil,
                subtitle?.unsupportedReason == nil
            else { throw Failure.missingTrack }
            if let audio {
                coordinator.selectedAudioID = audio.id
                // A remote selection never inherits a previous lossy treatment.
                coordinator.audioOutputMode = .original
            }
            coordinator.selectedSubtitleID = subtitle?.id
            coordinator.applyTrackSettings()
        case .synchronize(let audio, let subtitles):
            guard coordinator.commandAvailability.canEditTracks else { throw Failure.unavailable }
            coordinator.audioDelay = audio
            coordinator.subtitleDelay = subtitles
            coordinator.applyTrackSettings()
        case .play(let itemID, let fromBeginning):
            guard let item = library.resolve(itemID, queue: coordinator.queueItems),
                FileManager.default.fileExists(atPath: item.path)
            else { throw Failure.missingItem }
            if fromBeginning { coordinator.playQueueItemFromBeginning(item) } else { coordinator.playQueueItem(item) }
        case .next:
            guard let selected = coordinator.selectedURL,
                let current = coordinator.queueItems.firstIndex(where: { $0.url == selected }),
                coordinator.queueItems.indices.contains(current + 1)
            else { throw Failure.noNextItem }
            let next = coordinator.queueItems[current + 1]
            guard FileManager.default.fileExists(atPath: next.path) else { throw Failure.missingItem }
            coordinator.loadVideo(next.url, autoStart: true, continuingPlaylist: true)
        case .pause:
            guard coordinator.isStreaming, coordinator.commandAvailability.canTogglePlayback else {
                throw Failure.unavailable
            }
            // Explicit pause/resume, not toggle: rapid requests must not invert
            // an unconfirmed receiver state.
            guard coordinator.airPlay.pause() else { throw Failure.unavailable }
        case .resume:
            guard coordinator.isStreaming, coordinator.commandAvailability.canTogglePlayback else {
                throw Failure.unavailable
            }
            guard coordinator.airPlay.resume() else { throw Failure.unavailable }
        case .stop:
            coordinator.stop()
        case .seek(let seconds):
            guard coordinator.isStreaming, coordinator.commandAvailability.canSeek else { throw Failure.unavailable }
            coordinator.seek(to: seconds)
        case .skip(let seconds):
            guard coordinator.isStreaming, coordinator.commandAvailability.canSeek else { throw Failure.unavailable }
            coordinator.skip(by: seconds)
        default:
            throw Failure.unsupportedCommand
        }
    }
}
