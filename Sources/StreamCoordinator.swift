import AVFoundation
import AppKit
import Foundation
import OSLog
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class StreamCoordinator {
    // Local control identity, independent of the receiver's transport session.
    // Rotated even during analysis, when no AirPlay session exists yet.
    private(set) var remoteControlSessionID = UUID()
    func invalidateRemoteControlSession() {
        remoteControlSessionID = UUID()
    }
    private(set) var remoteReceiverObservation: AirPlayReceiverObservation?
    private(set) var selectedURL: URL?
    private(set) var probeInfo: MediaProbe?
    var status = "Listo"
    var detail = "Elige una película y AirCiller comprobará todas sus pistas."
    private(set) var isAnalyzing = false
    private var automaticStartWait = AutomaticPlaybackStartWait()
    var isWaitingToStart: Bool { automaticStartWait.isPending }
    var isPreparing = false
    var isStreaming = false
    var isPlaying = false
    var hasError = false
    var mediaDescription: String?
    var duration: Double = 0
    var currentTime: Double = 0
    @ObservationIgnored private var activeMovieTimeline: MoviePlaybackTimeline?
    private var moviePosition: Double {
        activeMovieTimeline?.sourcePosition(forPresentation: currentTime) ?? currentTime
    }
    private var movieDuration: Double { activeMovieTimeline?.sourceDuration ?? duration }
    private func presentationPosition(forMovie position: Double) -> Double {
        activeMovieTimeline?.presentationPosition(forSource: position) ?? position
    }
    var preparationProgress: Double = 0
    private(set) var demandAnalysis: MediaDemandAnalysis?
    private(set) var packagedDemandProfile: StreamDemandProfile?
    private(set) var streamTelemetry = HTTPServerTelemetry.empty
    private(set) var rebufferEvents = 0

    var audioTracks: [AudioTrack] = []
    var subtitleTracks: [SubtitleTrack] = []
    var chapters: [MediaChapter] = []
    var selectedAudioID: String?
    var selectedSubtitleID: String?
    var audioDelay: Double = 0
    var subtitleDelay: Double = 0
    var audioOutputMode: AudioOutputMode = .original
    private(set) var preferredAudioLanguage: String =
        UserDefaults.standard.string(forKey: "preferredAudioLanguage") ?? ""
    private(set) var preferredSubtitleLanguage: String =
        UserDefaults.standard.string(forKey: "preferredSubtitleLanguage") ?? ""
    private var remoteSessionAudioLanguage: String?
    private var remoteSessionSubtitleLanguage: String?
    var effectiveAudioLanguage: String { remoteSessionAudioLanguage ?? preferredAudioLanguage }
    var effectiveSubtitleLanguage: String { remoteSessionSubtitleLanguage ?? preferredSubtitleLanguage }

    func setRemoteLanguagePreferences(audio: String, subtitles: String, persistent: Bool) {
        if persistent {
            setPreferredAudioLanguage(audio)
            setPreferredSubtitleLanguage(subtitles)
            remoteSessionAudioLanguage = nil
            remoteSessionSubtitleLanguage = nil
        } else {
            remoteSessionAudioLanguage = audio
            remoteSessionSubtitleLanguage = subtitles
        }
    }
    private(set) var preferredSubtitleKind: SubtitleTrackPreference =
        UserDefaults.standard.string(forKey: "preferredSubtitleKind")
        .flatMap(SubtitleTrackPreference.init(rawValue:)) ?? .standard

    private(set) var recentItems: [RecentMediaItem] = HistoryStore.loadRecent()
    private(set) var queueItems: [QueueMediaItem] = HistoryStore.loadQueue()
    private(set) var seasonFolders: [SeasonFolder] = HistoryStore.loadSeasons()
    private(set) var isImportingLibrary = false
    private(set) var importedFileCount = 0
    private(set) var libraryImportMessage = ""
    private(set) var libraryImportIssues: [String] = []
    @ObservationIgnored private var libraryImportTask: Task<Void, Never>?
    @ObservationIgnored private var libraryImportID: UUID?
    @ObservationIgnored private var pendingLibraryURLs: [URL] = []
    private(set) var focusedQueueItemID: String?
    private(set) var focusedQueueSeasonID: String?
    var focusedRecentItemID: String?
    @ObservationIgnored private weak var libraryUndoManager: UndoManager?
    private(set) var unavailableLibraryPaths: Set<String> = []
    var showConversionAlert = false {
        didSet {
            if showConversionAlert && !oldValue {
                remoteConversionDecisionID = UUID()
                remoteConversionAudio = selectedAudio
            } else if !showConversionAlert {
                remoteConversionDecisionID = nil
                remoteConversionAudio = nil
            }
        }
    }
    private(set) var remoteConversionDecisionID: UUID?
    private var remoteConversionAudio: AudioTrack?
    private(set) var conversionReason = ""

    let player = AVPlayer()
    let network = NetworkMonitor()
    let airPlay = AirPlayController()
    private let nowPlaying = SystemNowPlayingController()
    private let playbackPower = PlaybackPowerAssertion()
    private let transitionPower = PlaybackPowerAssertion()
    private var playlistAudioConsent = PlaylistAudioConsent()
    #if AIRCILLER_UI_CHECKS
        func beginSyntheticPlaybackSessionForChecks() {
            precondition(CommandLine.arguments.contains("--skip-device-scan"))
            activeSessionID = UUID()
            playbackPower.begin()
            isStreaming = true
        }
        var playbackPowerIsActiveForChecks: Bool { playbackPower.isActive || transitionPower.isActive }

        func directStartupCheckpointForChecks(after suspension: @MainActor () async -> Void) async throws {
            guard let sessionID = activeSessionID else { preconditionFailure("Requires a synthetic session") }
            await suspension()
            try requireCurrentStreamSession(sessionID)
        }

        func beginSyntheticAuthorizationRenewalForChecks() {
            precondition(CommandLine.arguments.contains("--skip-device-scan"))
            authorizationRenewalSessionID = remoteControlSessionID
            transitionPower.begin()
        }
    #endif
    private let playbackLogger = Logger(subsystem: "local.carlosciller.AirCiller", category: "Playback")
    @ObservationIgnored private let launchOptions = AirCillerLaunchOptions()

    @ObservationIgnored private var server: LocalHTTPServer?
    @ObservationIgnored private var ffmpegProcess: Process?
    @ObservationIgnored private var ffmpegLog: ProcessLogBuffer?
    @ObservationIgnored private var temporaryDirectory: URL?
    @ObservationIgnored private var startupTrace: PlaybackStartupTrace?
    @ObservationIgnored private var startupSpans: [PlaybackStartupTrace.Stage: PlaybackStartupTrace.SpanToken] = [:]
    @ObservationIgnored private var startupUsedCache = false
    // While HLS children run, their owning task removes the directory only after
    // cancellation has joined them. Stop can detach the session immediately.
    @ObservationIgnored private var preparingHLSDirectory: URL?

    var startupDiagnostics: String {
        guard let trace = startupTrace else { return "" }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(trace.snapshot()),
            let json = String(data: data, encoding: .utf8)
        else { return "" }
        return "\n\nHLS startup timing (preparation to receiver request, not first visible frame)\n"
            + "Base cache hit: \(startupUsedCache)\n" + json
    }

    var activePreparedDirectory: URL? { temporaryDirectory }
    #if AIRCILLER_PLAYBACK_CHECKS
        func playbackCheckPrepareBitmap() throws {
            guard airPlay.playbackCheckLocalOnly, let url = selectedURL, let info = probeInfo,
                selectedSubtitle?.usesBitmapOCR == true, selectedAudio?.canPassThrough == true,
                audioOutputMode == .original, (45...180).contains(info.duration)
            else { throw PlaybackCheckFailure.unsupportedFixture }
            if info.isHDR {
                beginDirectHDRSubtitleStreaming(url: url, info: info, requestedTime: 0)
            } else {
                beginStreaming(url: url, info: info, requestedTime: 0)
            }
        }

        @ObservationIgnored var onPlaybackCheckLoad: ((URL) -> Void)?
        // Only the opt-in runner owns this disposable cache. Nil keeps checks cold.
        @ObservationIgnored var playbackCheckPreparedMediaCache: PreparedMediaCache?
        var playbackCheckStartupSnapshot: PlaybackStartupTrace.Snapshot? { startupTrace?.snapshot() }
        var playbackCheckUsedPreparedMediaCache: Bool { startupUsedCache }
        var playbackCheckPreparationProcessIsRunning: Bool { ffmpegProcess?.isRunning == true }
        var playbackCheckRuntimeIsIdle: Bool {
            server == nil && ffmpegProcess == nil && streamTask == nil && activeSessionID == nil
                && player.currentItem == nil && !airPlay.isSessionActive
                && !isPreparing && !isStreaming && !isPlaying
                && !isWaitingToStart
        }
    #endif
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private let authorizationPreflight = PlaybackAuthorizationPreflight()
    @ObservationIgnored private var authorizationRetryPolicy = AirPlayAuthorizationRetryPolicy()
    @ObservationIgnored private var authorizationRenewalSessionID: UUID?
    @ObservationIgnored private let mediaAnalysisTasks = MediaAnalysisTasks()
    @ObservationIgnored private var activeAnalysisID: UUID?
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var itemEndObserver: NSObjectProtocol?
    @ObservationIgnored private var itemErrorObserver: NSObjectProtocol?
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var pendingStartTime: Double = 0
    @ObservationIgnored private var lastHistorySave = Date.distantPast
    @ObservationIgnored private var activeSessionID: UUID?
    @ObservationIgnored private var lastRebufferEvent = Date.distantPast

    init() {
        seasonFolders = HistoryStore.recoveringSeasons(queue: queueItems, stored: seasonFolders)
        #if !AIRCILLER_PLAYBACK_CHECKS && !AIRCILLER_UI_CHECKS
            Self.cleanupStaleBuffers()
        #endif
        player.allowsExternalPlayback = true
        player.automaticallyWaitsToMinimizeStalling = true

        airPlay.onReceiverPlaybackUpdate = { [weak self] observation in
            self?.remoteReceiverObservation = observation
        }
        airPlay.onPlaybackUpdate = { [weak self] position, reportedDuration, playing in
            guard let self else { return }
            let previousState = self.isPlaying
            let previousPosition = self.currentTime
            if reportedDuration.isFinite, reportedDuration > 0 {
                self.duration = reportedDuration
            }
            if position.isFinite {
                self.currentTime = min(self.duration, max(0, position))
            }
            let playbackAdvanced = position.isFinite && position > previousPosition + 0.05
            self.isPlaying = playing
            let queueIndex = self.selectedURL.flatMap { selectedURL in
                self.queueItems.firstIndex(where: { $0.path == selectedURL.path })
            }
            self.nowPlaying.update(
                title: self.selectedURL?.deletingPathExtension().lastPathComponent ?? "AirCiller",
                duration: self.duration,
                position: self.currentTime,
                playing: playing,
                queueIndex: queueIndex,
                queueCount: queueIndex == nil ? nil : self.queueItems.count
            )
            if self.isStreaming, previousState != playing || (playing && playbackAdvanced) {
                self.status =
                    playing
                    ? L10n.format(
                        "Reproduciendo en %@", self.airPlay.selectedDevice?.name ?? "Apple TV")
                    : L10n.text("En pausa desde el Apple TV")
                if previousState != playing {
                    self.detail =
                        playing
                        ? L10n.text("El mando del Apple TV ha reanudado la película.")
                        : L10n.text("La pausa del mando se ha sincronizado con AirCiller.")
                } else if playbackAdvanced {
                    self.detail = L10n.text("La reproducción está sincronizada con el Apple TV.")
                }
            }
            self.saveCurrentPosition(force: false)
        }
        airPlay.onPlaybackWaiting = { [weak self] isRebuffering in
            guard let self, isRebuffering else { return }
            let now = Date()
            if now.timeIntervalSince(self.lastRebufferEvent) >= 3 {
                self.rebufferEvents += 1
                self.lastRebufferEvent = now
            }
            self.status = "Apple TV está rellenando el buffer…"
            self.detail = "AirCiller mantiene el stream original y está midiendo el margen real de la red local."
        }
        airPlay.onPlaybackEnded = { [weak self] in
            self?.playbackFinished()
        }
        airPlay.onPlaybackStopped = { [weak self] in
            self?.playbackStoppedByReceiver()
        }
        airPlay.onPlaybackError = { [weak self] message in
            guard let self else { return }
            self.cleanupRuntime()
            self.isPreparing = false
            self.isStreaming = false
            self.isPlaying = false
            let title =
                message == L10n.text("Se perdió el canal de control con el Apple TV.")
                ? L10n.text("Se perdió la conexión con el Apple TV.")
                : L10n.text("Apple TV rechazó la reproducción")
            self.presentError(title: title, detail: message)
        }
        airPlay.onAuthorizationRequired = { [weak self] message in
            guard let self else { return }
            let retryTime = self.moviePosition
            self.cleanupRuntime()
            self.requestAuthorizationRenewal(message: message, retryAt: retryTime)
        }
        airPlay.onPairingSucceeded = { [weak self] shouldResumePlayback in
            guard let self, shouldResumePlayback, self.selectedURL != nil else { return }
            self.authorizationRenewalSessionID = nil
            self.continueStart(at: self.pendingStartTime)
        }
        airPlay.onPairingCancelled = { [weak self] in
            guard let self else { return }
            let owner = self.authorizationRenewalSessionID
            self.authorizationRenewalSessionID = nil
            guard owner == self.remoteControlSessionID,
                self.activeSessionID == nil, !self.isAnalyzing, !self.isWaitingToStart,
                !self.showConversionAlert
            else { return }
            self.transitionPower.end()
            self.isPreparing = false
            self.status = "Operación cancelada."
            self.detail = "El vídeo se enviará sin recodificar. Elige las pistas y pulsa Reproducir."
        }

        nowPlaying.onPlay = { [weak self] in
            guard let self, self.isStreaming, !self.isPlaying else { return }
            self.airPlay.resume()
        }
        nowPlaying.onPause = { [weak self] in
            guard let self, self.isStreaming, self.isPlaying else { return }
            self.airPlay.pause()
        }
        nowPlaying.onToggle = { [weak self] in
            guard let self, self.isStreaming else { return }
            self.togglePlayback()
        }
        nowPlaying.onStop = { [weak self] in
            self?.stop()
        }
        nowPlaying.onSeek = { [weak self] position in
            self?.seek(to: position)
        }
        nowPlaying.onSkip = { [weak self] interval in
            self?.skip(by: interval)
        }

        #if !AIRCILLER_PLAYBACK_CHECKS && !AIRCILLER_UI_CHECKS
            Task { [weak self] in
                guard let self else { return }
                if !self.launchOptions.skipsDeviceScan {
                    await self.airPlay.refreshDevices()
                }
                if let directTestURL = self.launchOptions.directAirPlayTestURL {
                    do {
                        self.playbackPower.begin()
                        self.isPreparing = true
                        self.status = "Prueba AirPlay directa…"
                        self.detail = "Esperando confirmación real del Apple TV."
                        try await self.airPlay.startPlayback(url: directTestURL, position: 0)
                        self.isPreparing = false
                        self.isStreaming = true
                        self.isPlaying = true
                        self.status = L10n.format(
                            "Prueba reproduciéndose en %@", self.airPlay.selectedDevice?.name ?? "Apple TV")
                        self.detail = "El receptor ha confirmado una duración válida."
                    } catch {
                        self.playbackPower.end()
                        self.isPreparing = false
                        self.presentError(title: "Falló la prueba AirPlay directa", detail: error.localizedDescription)
                        self.playbackLogger.error("Prueba directa: \(error.localizedDescription, privacy: .public)")
                    }
                } else if let autostartURL = self.launchOptions.autostartFileURL {
                    self.loadVideo(autostartURL, autoStart: true)
                }
            }

        #endif

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.stop(resetStatus: false)
            }
        }

    }

    isolated deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
        if let itemEndObserver { NotificationCenter.default.removeObserver(itemEndObserver) }
        if let itemErrorObserver { NotificationCenter.default.removeObserver(itemErrorObserver) }
    }

    var selectedAudio: AudioTrack? {
        audioTracks.first(where: { $0.id == selectedAudioID })
    }

    var commandAvailability: PlaybackCommandAvailability {
        PlaybackCommandAvailability(
            hasFile: selectedURL != nil,
            hasProbe: probeInfo != nil,
            isAnalyzing: isAnalyzing,
            isWaitingToStart: isWaitingToStart,
            isPreparing: isPreparing,
            isStreaming: isStreaming,
            isCheckingAuthorization: airPlay.authorizationState == .checking,
            isPairing: airPlay.isPairingPresented,
            isAwaitingConversion: showConversionAlert,
            duration: duration,
            hasChapters: !chapters.isEmpty
        )
    }

    var selectedSubtitle: SubtitleTrack? {
        subtitleTracks.first(where: { $0.id == selectedSubtitleID })
    }

    var trackSettings: TrackSettings {
        get {
            TrackSettings(
                audioID: selectedAudioID, subtitleID: selectedSubtitleID,
                audioDelay: audioDelay, subtitleDelay: subtitleDelay, audioOutputMode: audioOutputMode
            )
        }
        set {
            selectedAudioID = newValue.audioID
            selectedSubtitleID = newValue.subtitleID
            audioDelay = newValue.audioDelay
            subtitleDelay = newValue.subtitleDelay
            audioOutputMode = newValue.audioOutputMode
        }
    }

    var diagnosticPlaybackRoute: String {
        guard probeInfo != nil else { return "not prepared" }
        return probeInfo?.isHDR == true && selectedSubtitle != nil
            ? "direct MP4 (HDR with selectable subtitle)"
            : "HLS/fMP4 VOD"
    }

    var mediaBadges: [MediaBadge] {
        guard let probeInfo else { return [] }
        var badges: [MediaBadge] = []

        let width = probeInfo.width ?? 0
        let height = probeInfo.height ?? 0
        let resolution = MediaPresentation.resolutionLabel(width: probeInfo.width, height: probeInfo.height)
        let dimensions =
            width > 0 && height > 0
            ? "\(width) × \(height)" : L10n.text("Dimensiones desconocidas")
        badges.append(MediaBadge(id: "resolution", label: "Resolución", value: resolution, detail: dimensions))

        if probeInfo.isDolbyVision {
            let profile = MediaPresentation.dolbyVisionProfile(
                probeInfo.dolbyVisionProfile,
                compatibilityID: probeInfo.dolbyVisionCompatibilityID
            )
            badges.append(
                MediaBadge(
                    id: "dynamic-range",
                    label: "Rango dinámico",
                    value: "Dolby Vision",
                    detail: profile
                ))
        } else if probeInfo.isHDR {
            let format = probeInfo.colorTransfer?.lowercased() == "arib-std-b67" ? "HLG" : "HDR10"
            badges.append(
                MediaBadge(
                    id: "dynamic-range",
                    label: "Rango dinámico",
                    value: format,
                    detail: "Alto rango dinámico"
                ))
        } else {
            badges.append(
                MediaBadge(
                    id: "dynamic-range",
                    label: "Rango dinámico",
                    value: "SDR",
                    detail: "Rango estándar"
                ))
        }

        if let audio = selectedAudio {
            let value = audio.isAtmos ? "Dolby Atmos" : (audio.channelDescription ?? "Audio")
            let detail =
                audio.isAtmos
                ? [audio.codecDisplayName, audio.channelDescription].compactMap { $0 }.joined(separator: " · ")
                : audio.codecDisplayName
            badges.append(
                MediaBadge(
                    id: "audio",
                    label: "Audio",
                    value: value,
                    detail: detail
                ))
        } else {
            badges.append(
                MediaBadge(id: "audio", label: "Audio", value: "Sin audio", detail: "No hay pista seleccionada"))
        }

        if !subtitleTracks.isEmpty {
            let selected = selectedSubtitle?.displayName ?? "Desactivados"
            badges.append(
                MediaBadge(
                    id: "subtitles",
                    label: "Subtítulos",
                    value: subtitleTracks.count == 1
                        ? L10n.text("1 pista")
                        : L10n.format("%lld pistas", Int64(subtitleTracks.count)),
                    detail: selected
                ))
        } else {
            badges.append(
                MediaBadge(
                    id: "subtitles",
                    label: "Subtítulos",
                    value: "Sin pistas",
                    detail: "No disponibles"
                ))
        }
        return badges
    }

    var videoPlan: String {
        L10n.text(probeInfo == nil ? "Vídeo sin analizar" : "Vídeo · copia exacta, sin recodificar")
    }

    var audioPlan: String {
        guard let selectedAudio else { return L10n.text("Sin audio") }
        switch audioOutputMode {
        case .losslessFLAC:
            return L10n.text("Audio · conversión elegida a FLAC sin pérdida")
        case .original:
            return selectedAudio.canPassThrough
                ? L10n.format(
                    "Audio · %@, sin recodificar", selectedAudio.technicalDescription)
                : L10n.format(
                    "Audio · %@, requiere conversión autorizada", selectedAudio.technicalDescription)
        case .compatible:
            return L10n.text("Audio · conversión elegida a E-AC-3 (hasta 5.1)")
        case .stereo:
            return L10n.text("Audio · conversión elegida a AAC estéreo")
        }
    }

    var canOfferLosslessAudioConversion: Bool {
        var settings = trackSettings
        settings.audioOutputMode = .losslessFLAC
        return settings.hasSupportedAudioOutput(audio: selectedAudio, isHDR: probeInfo?.isHDR)
    }

    var subtitlePlan: String {
        guard let subtitle = selectedSubtitle else { return L10n.text("Subtítulos · desactivados") }
        if subtitle.usesBitmapOCR {
            return probeInfo?.isHDR == true
                ? L10n.format(
                    "Subtítulos · %@, OCR local a texto seleccionable dentro del MP4", subtitle.displayName)
                : L10n.format(
                    "Subtítulos · %@, OCR local bajo demanda a WebVTT", subtitle.displayName)
        }
        guard subtitle.isSelectable else {
            return L10n.format("Subtítulos · %@, no compatibles todavía", subtitle.displayName)
        }
        if probeInfo?.isHDR == true {
            return subtitle.usesAdvancedTextStyling
                ? L10n.format(
                    "Subtítulos · %@, integrados en el MP4 con estilo simplificado", subtitle.displayName)
                : L10n.format("Subtítulos · %@, integrados en el MP4", subtitle.displayName)
        }
        return subtitle.usesAdvancedTextStyling
            ? L10n.format("Subtítulos · %@, WebVTT con posición nativa", subtitle.displayName)
            : L10n.format("Subtítulos · %@, convertidos a WebVTT", subtitle.displayName)
    }

    var streamDemandProfile: StreamDemandProfile? {
        if let packagedDemandProfile { return packagedDemandProfile }
        guard let probeInfo else { return nil }
        guard let demandAnalysis else {
            return StreamDemandAnalyzer.estimatedProfile(probe: probeInfo)
        }

        let audioStreamIndex: Int?
        let fixedAudioBitsPerSecond: Double?
        switch audioOutputMode {
        case .losslessFLAC:
            audioStreamIndex = selectedAudio?.streamIndex
            fixedAudioBitsPerSecond = nil
        case .original:
            audioStreamIndex = selectedAudio?.streamIndex
            fixedAudioBitsPerSecond = nil
        case .compatible:
            audioStreamIndex = nil
            fixedAudioBitsPerSecond = selectedAudio == nil ? nil : 640_000
        case .stereo:
            audioStreamIndex = nil
            fixedAudioBitsPerSecond = selectedAudio == nil ? nil : 256_000
        }
        return demandAnalysis.profile(
            videoStreamIndex: probeInfo.videoStreamIndex,
            audioStreamIndex: audioStreamIndex,
            fixedAudioBitsPerSecond: fixedAudioBitsPerSecond
        )
    }

    var streamHealthLevel: StreamHealthLevel {
        StreamHealth.level(
            capacity: streamTelemetry.observedCapacityBitsPerSecond,
            demand: streamDemandProfile,
            unexpectedErrors: streamTelemetry.unexpectedErrors
        )
    }

    func setPreferredAudioLanguage(_ language: String) {
        preferredAudioLanguage = language
        UserDefaults.standard.set(language, forKey: "preferredAudioLanguage")
    }

    func setPreferredSubtitleLanguage(_ language: String) {
        preferredSubtitleLanguage = language
        UserDefaults.standard.set(language, forKey: "preferredSubtitleLanguage")
    }

    func setPreferredSubtitleKind(_ preference: SubtitleTrackPreference) {
        preferredSubtitleKind = preference
        UserDefaults.standard.set(preference.rawValue, forKey: "preferredSubtitleKind")
    }

    func chooseVideos() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("Elegir películas")
        panel.prompt = L10n.text("Abrir")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = MediaFileTypes.contentTypes

        guard panel.runModal() == .OK, let first = panel.urls.first else { return }
        handleURLs([first] + Array(panel.urls.dropFirst()))
    }

    func addToQueue() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("Añadir a la playlist")
        panel.prompt = L10n.text("Añadir")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = MediaFileTypes.contentTypes
        guard panel.runModal() == .OK else { return }
        handleURLs(panel.urls, analyzeFirst: false)
    }

    func handleURLs(_ urls: [URL], analyzeFirst: Bool = true) {
        libraryImportIssues = urls.filter {
            !MediaFileTypes.accepts($0)
                && !($0.isFileURL && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
        }.map { L10n.format("%@: formato no compatible", $0.lastPathComponent) }
        libraryImportMessage =
            libraryImportIssues.isEmpty
            ? ""
            : L10n.format("%lld elementos no se pudieron añadir", Int64(libraryImportIssues.count))
        if urls.contains(where: {
            $0.isFileURL && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }) {
            importLibraryFolders(urls)
            return
        }
        let videos = urls.filter(MediaFileTypes.accepts)
        guard let first = videos.first else {
            guard !commandAvailability.canStop else { return }
            presentError(
                title: "No hay ninguna película compatible",
                detail: "Arrastra o abre un archivo MKV, MP4, M4V, MOV, TS, MTS o M2TS."
            )
            return
        }
        enqueue(videos)
        guard analyzeFirst, !commandAvailability.canStop else { return }
        loadVideo(first, autoStart: false)
    }

    func cancelLibraryImport() {
        pendingLibraryURLs.removeAll()
        libraryImportID = nil
        libraryImportTask?.cancel()
        libraryImportTask = nil
        isImportingLibrary = false
        libraryImportMessage = L10n.text("Importación cancelada")
    }

    private func importLibraryFolders(_ urls: [URL]) {
        enqueue(
            urls.filter {
                MediaFileTypes.accepts($0)
                    && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true
            })
        pendingLibraryURLs.append(
            contentsOf: urls.filter {
                $0.isFileURL && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            })
        guard !isImportingLibrary else { return }
        let importID = UUID()
        libraryImportID = importID
        isImportingLibrary = true
        importedFileCount = 0
        libraryImportMessage = L10n.text("Añadiendo archivos…")
        // Standalone files are admitted immediately, independently of folder enumeration.
        libraryImportTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.libraryImportID == importID {
                    self.libraryImportID = nil
                    self.libraryImportTask = nil
                    self.isImportingLibrary = false
                }
            }
            var failures: [String] = []
            while !self.pendingLibraryURLs.isEmpty {
                guard !Task.isCancelled, self.libraryImportID == importID else { return }
                let url = self.pendingLibraryURLs.removeFirst()
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                    failures.append(url.path)
                    continue
                }
                let worker = Task.detached(priority: .userInitiated) {
                    try SeasonFolderImporter.scan(url) { [weak self] count in
                        Task { @MainActor [weak self] in
                            guard let self, self.libraryImportID == importID else { return }
                            self.libraryImportMessage = L10n.format("%lld elementos revisados", Int64(count))
                        }
                    }
                }
                do {
                    let result = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: {
                        worker.cancel()
                    }
                    try Task.checkCancellation()
                    guard self.libraryImportID == importID else { return }
                    let previousCount = self.queueItems.count
                    self.admitSeason(url, movies: result.movies)
                    self.importedFileCount += self.queueItems.count - previousCount
                    failures.append(contentsOf: result.unreadablePaths)
                    if result.movies.isEmpty { failures.append(url.path) }
                } catch is CancellationError {
                    return
                } catch {
                    failures.append(url.path)
                }
            }
            let added = L10n.format(
                self.importedFileCount == 1 ? "%lld archivo añadido" : "%lld archivos añadidos",
                Int64(self.importedFileCount))
            if failures.isEmpty {
                self.libraryImportMessage =
                    self.importedFileCount == 0
                    ? L10n.text("No hay archivos nuevos que añadir") : added
            } else {
                let unavailable = L10n.format(
                    failures.count == 1 ? "%lld ubicación no disponible" : "%lld ubicaciones no disponibles",
                    Int64(failures.count))
                self.libraryImportMessage = "\(added); \(unavailable)"
            }
            self.libraryImportIssues.append(
                contentsOf: failures.map {
                    L10n.format(
                        "%@: no se pudo leer la carpeta o no contiene vídeos compatibles",
                        URL(fileURLWithPath: $0).lastPathComponent)
                })
        }
    }

    private func admitSeason(_ folder: URL, movies: [URL]) {
        guard !movies.isEmpty else { return }
        let path = folder.standardizedFileURL.path
        if !seasonFolders.contains(where: { $0.id == path }) {
            seasonFolders.append(SeasonFolder(path: path, title: folder.lastPathComponent, isExpanded: true))
        }
        enqueue(movies)
        let importedPaths = Set(movies.map(\.path))
        for index in queueItems.indices where importedPaths.contains(queueItems[index].path) {
            if queueItems[index].seasonID == nil { queueItems[index].seasonID = path }
        }
        normalizeSeasonOrder()
        HistoryStore.saveQueue(queueItems)
        HistoryStore.saveSeasons(seasonFolders)
    }

    private func normalizeSeasonOrder() {
        var ordered: [QueueMediaItem] = []
        var seen = Set<String>()
        for item in queueItems {
            if let seasonID = item.seasonID {
                if seen.insert(seasonID).inserted {
                    ordered.append(contentsOf: queueItems.filter { $0.seasonID == seasonID })
                }
            } else {
                ordered.append(item)
            }
        }
        queueItems = ordered
    }

    func setSeasonExpanded(_ id: String, expanded: Bool) {
        guard let index = seasonFolders.firstIndex(where: { $0.id == id }) else { return }
        seasonFolders[index].isExpanded = expanded
        HistoryStore.saveSeasons(seasonFolders)
    }

    func setWatched(_ item: QueueMediaItem, watched: Bool) {
        guard let index = queueItems.firstIndex(where: { $0.id == item.id }) else { return }
        guard queueItems[index].watched != watched else { return }
        registerWatchedUndo(
            id: item.id, previous: queueItems[index].watched,
            actionName: watched ? "Marcar como visto" : "Marcar como pendiente")
        queueItems[index].watched = watched
        HistoryStore.saveQueue(queueItems)
    }

    private func registerWatchedUndo(id: String, previous: Bool?, actionName: String) {
        libraryUndoManager?.registerUndo(withTarget: self) { coordinator in
            MainActor.assumeIsolated {
                guard let index = coordinator.queueItems.firstIndex(where: { $0.id == id }) else { return }
                coordinator.registerWatchedUndo(
                    id: id, previous: coordinator.queueItems[index].watched, actionName: actionName)
                coordinator.queueItems[index].watched = previous
                HistoryStore.saveQueue(coordinator.queueItems)
            }
        }
        libraryUndoManager?.setActionName(L10n.text(actionName))
    }

    func removeSeason(_ id: String) {
        let previousItems = queueItems
        let previousFocus = focusedQueueItemID
        queueItems.removeAll { $0.seasonID == id }
        if !queueItems.contains(where: { $0.id == focusedQueueItemID }) { focusedQueueItemID = nil }
        HistoryStore.saveQueue(queueItems)
        registerQueueUndo(before: previousItems, focus: previousFocus, actionName: "Quitar de la playlist")
        if focusedQueueSeasonID == id { focusedQueueSeasonID = nil }
    }

    func chooseExternalSubtitle() -> SubtitleTrack? {
        guard selectedURL != nil else { return nil }
        let panel = NSOpenPanel()
        panel.title = L10n.text("Añadir subtítulos")
        panel.prompt = L10n.text("Añadir")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ["srt", "ass", "ssa", "vtt", "sup", "idx", "sub"].compactMap { extensionName in
            UTType(filenameExtension: extensionName)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return registerExternalSubtitle(url)
    }

    func registerExternalSubtitle(_ url: URL) -> SubtitleTrack? {
        guard selectedURL != nil else { return nil }
        do {
            let tracks = try MediaProbeService.externalTracks(url: url)
            for track in tracks where !subtitleTracks.contains(where: { $0.id == track.id }) {
                subtitleTracks.append(track)
            }
            return tracks.first(where: \.isDefault) ?? tracks.first
        } catch {
            hasError = true
            status = "No se pudieron añadir los subtítulos"
            detail = error.localizedDescription
            return nil
        }
    }

    func playRecent(_ item: RecentMediaItem) {
        guard libraryFileExists(item.url) else { return }
        loadVideo(item.url, autoStart: true)
    }

    func loadVideo(
        _ url: URL, autoStart: Bool, startingAt requestedStart: Double? = nil,
        continuingPlaylist: Bool = false
    ) {
        #if AIRCILLER_PLAYBACK_CHECKS
            onPlaybackCheckLoad?(url)
        #endif
        let commandLineSubtitleIndex = autoStart ? launchOptions.subtitleStreamIndex : nil
        mediaAnalysisTasks.cancelAll()
        if autoStart { transitionPower.begin() }
        stop(resetStatus: false, preservingPlaylist: continuingPlaylist, preservingTransition: autoStart)
        selectedURL = url
        probeInfo = nil
        audioTracks = []
        subtitleTracks = []
        chapters = []
        selectedAudioID = nil
        selectedSubtitleID = nil
        audioDelay = 0
        subtitleDelay = 0
        audioOutputMode = .original
        mediaDescription = nil
        duration = 0
        demandAnalysis = nil
        packagedDemandProfile = nil
        streamTelemetry = .empty
        rebufferEvents = 0
        lastRebufferEvent = .distantPast
        let queued = queueItems.first(where: { $0.path == url.path })
        currentTime =
            requestedStart
            ?? (queued?.watched == true || queued?.progress == 1 ? 0 : queued?.lastPosition)
            ?? recentItems.first(where: { $0.path == url.path })?.lastPosition ?? 0
        hasError = false
        status = "Analizando la película…"
        detail = "Comprobando duración, Dolby Vision, HDR, audio, subtítulos y capítulos."
        let analysisID = UUID()
        activeAnalysisID = analysisID
        isAnalyzing = true
        touchRecent(url: url, duration: 0, position: currentTime)

        mediaAnalysisTasks.replacePrimary(
            with: Task { [weak self] in
                guard let self else { return }
                do {
                    let info = try await MediaProbeService.probe(url: url)
                    try Task.checkCancellation()
                    guard self.activeAnalysisID == analysisID else { return }
                    let automaticStartID = autoStart ? self.automaticStartWait.begin() : nil
                    self.activeAnalysisID = nil
                    self.isAnalyzing = false
                    self.probeInfo = info
                    self.audioTracks = info.audioTracks
                    self.subtitleTracks = info.subtitleTracks
                    self.chapters = info.chapters
                    if !self.effectiveAudioLanguage.isEmpty,
                        let preferredAudio = AudioTrackSelection.preferredTrack(
                            in: info.audioTracks,
                            language: self.effectiveAudioLanguage
                        )
                    {
                        self.selectedAudioID = preferredAudio.id
                    } else {
                        self.selectedAudioID =
                            (info.audioTracks.first(where: \.isDefault) ?? info.audioTracks.first)?.id
                    }
                    if let commandLineSubtitleIndex {
                        self.selectedSubtitleID =
                            info.subtitleTracks.first(where: {
                                $0.streamIndex == commandLineSubtitleIndex
                            })?.id
                    } else if !self.effectiveSubtitleLanguage.isEmpty {
                        self.selectedSubtitleID =
                            SubtitleTrackSelection.preferredTrack(
                                in: info.subtitleTracks,
                                language: self.effectiveSubtitleLanguage,
                                preference: self.preferredSubtitleKind
                            )?.id
                    }
                    self.duration = info.duration
                    if self.currentTime >= max(0, info.duration - 30) {
                        self.currentTime = 0
                    }
                    self.mediaDescription = info.displayDescription
                    self.startDemandAnalysis(url: url, probe: info)
                    self.status = "Lista para reproducir"
                    self.detail =
                        info.isDolbyVision
                        ? "Dolby Vision se mantendrá intacto. Elige las pistas y pulsa Reproducir."
                        : "El vídeo se enviará sin recodificar. Elige las pistas y pulsa Reproducir."
                    self.touchRecent(url: url, duration: info.duration, position: self.currentTime)
                    if let automaticStartID {
                        await self.startAfterNetworkSettles(waitID: automaticStartID)
                    }
                } catch is CancellationError {
                    if self.activeAnalysisID == analysisID {
                        self.activeAnalysisID = nil
                        self.isAnalyzing = false
                    }
                    return
                } catch {
                    guard !Task.isCancelled, self.activeAnalysisID == analysisID else { return }
                    self.activeAnalysisID = nil
                    self.isAnalyzing = false
                    self.hasError = true
                    self.transitionPower.end()
                    self.status = "No se pudo analizar la película"
                    self.detail = error.localizedDescription
                }
            })
    }

    func start() {
        start(at: moviePosition)
    }

    func start(at requestedTime: Double) {
        remoteReceiverObservation = nil
        cancelAuthorizationPreflight()
        authorizationRetryPolicy.reset()
        continueStart(at: requestedTime)
    }

    private func startAfterNetworkSettles(waitID: UUID) async {
        defer { automaticStartWait.finish(waitID) }
        guard !Task.isCancelled, automaticStartWait.id == waitID else { return }
        let deadline = Date().addingTimeInterval(3)
        while !network.isReady, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled, automaticStartWait.id == waitID else { return }
        }
        guard !Task.isCancelled, automaticStartWait.finish(waitID) else { return }
        start()
    }

    private func startDemandAnalysis(url: URL, probe: MediaProbe) {
        mediaAnalysisTasks.replaceDemand(
            with: Task { [weak self] in
                guard let self else { return }
                do {
                    let analysis = try await StreamDemandAnalyzer.analyze(
                        url: url,
                        duration: probe.duration
                    )
                    try Task.checkCancellation()
                    guard self.selectedURL == url else { return }
                    self.demandAnalysis = analysis
                } catch is CancellationError {
                    return
                } catch {
                    self.playbackLogger.warning(
                        "No se pudieron calcular los picos del archivo: \(error.localizedDescription, privacy: .private)"
                    )
                }
            })
    }

    private func continueStart(at requestedTime: Double) {
        guard let selectedURL, let info = probeInfo else { return }
        guard FileManager.default.fileExists(atPath: selectedURL.path) else {
            presentError(title: "No se encuentra el archivo", detail: "Puede haberse movido o eliminado.")
            return
        }
        guard network.isReady else {
            presentError(
                title: "No hay una red local preparada",
                detail: "Conecta el Mac y el Apple TV a la misma red Wi‑Fi o Ethernet y vuelve a intentarlo."
            )
            return
        }
        guard airPlay.selectedDevice != nil else {
            presentError(
                title: "Elige un Apple TV",
                detail: airPlay.scanError ?? "Pulsa Buscar Apple TV y selecciona el receptor antes de reproducir."
            )
            Task { [weak self] in await self?.airPlay.refreshDevices() }
            return
        }
        if airPlay.isCheckingAuthorization {
            pendingStartTime = requestedTime
            isPreparing = true
            status = "Comprobando autorización de AirPlay…"
            detail = "AirCiller continuará automáticamente cuando macOS confirme el acceso seguro."
            authorizationPreflight.start {
                try await self.airPlay.refreshAuthorization()
            } onSuccess: { [weak self] in
                guard let self, self.selectedURL == selectedURL else { return }
                self.isPreparing = false
                self.continueStart(at: requestedTime)
            } onFailure: { [weak self] error in
                self?.isPreparing = false
                self?.presentError(title: "No se pudo comprobar la autorización", detail: error.localizedDescription)
            }
            return
        }
        guard ["hevc", "h264"].contains(info.videoCodec.lowercased()) else {
            presentError(
                title: "Vídeo no compatible sin conversión",
                detail: L10n.format(
                    "El archivo usa %@. AirCiller no recodificará el vídeo sin pedirlo.",
                    info.videoCodec.uppercased())
            )
            return
        }
        if let subtitle = selectedSubtitle, let reason = subtitle.unsupportedReason {
            presentError(title: "Esta pista no puede enviarse todavía", detail: reason)
            return
        }
        if audioOutputMode == .original, let audio = selectedAudio,
            let authorized = playlistAudioConsent.authorizedOutput(
                for: audio, isDirectMP4: info.isHDR && selectedSubtitle != nil, audioDelay: audioDelay)
        {
            audioOutputMode = authorized
        }
        guard
            audioOutputMode.isAvailable(
                audio: selectedAudio, isDirectMP4: info.isHDR && selectedSubtitle != nil
            ), audioOutputMode != .losslessFLAC || (audioDelay.isFinite && abs(audioDelay) < 0.001)
        else {
            presentError(
                title: "Conversión de audio no disponible",
                detail:
                    "La conversión a FLAC necesita una pista compatible con precisión y canales conocidos y la ruta HLS. Elige otra salida de audio."
            )
            return
        }
        if let audio = selectedAudio,
            audioOutputMode == .original,
            !audio.canPassThrough
        {
            pendingStartTime = requestedTime
            conversionReason = L10n.format(
                "La pista elegida usa %@, que Apple TV no admite en este HLS. AirCiller puede convertir solamente el audio a E-AC-3 y mantendrá el vídeo intacto.",
                audio.codec.uppercased())
            if canOfferLosslessAudioConversion {
                conversionReason = L10n.text(
                    "Esta pista necesita conversión para reproducirse. FLAC conserva las muestras y todos los canales; E-AC-3 añade pérdida y admite hasta 5.1 canales. Los objetos Atmos no se conservan. El vídeo y el archivo original no cambiarán."
                )
            } else if audio.codec.lowercased().hasPrefix("pcm_") {
                conversionReason = L10n.text(
                    "El envío de PCM original no está validado en esta ruta de AirCiller. E-AC-3 añade pérdida. Para conservar las muestras, cancela y elige FLAC sin pérdida en las opciones de audio, si está disponible. El vídeo y el archivo original no cambiarán."
                )
            } else if audio.codec.lowercased() == "flac" {
                conversionReason = L10n.format(
                    "La distribución de canales FLAC (%@) no se conserva con el empaquetado actual. Elige otra pista o autoriza convertir solo el audio a E-AC-3. No se cambiará el vídeo ni el archivo original.",
                    audio.channelLayout ?? L10n.text("Desconocido"))
            }
            transitionPower.begin()
            status = "Esperando autorización de audio"
            detail = "Autoriza la conversión en el Mac para continuar la playlist."
            conversionReason +=
                "\n\n"
                + L10n.text(
                    "La autorización se aplicará a los siguientes episodios de esta sesión que necesiten la misma conversión. Se borrará al detener o elegir otra reproducción."
                )
            showConversionAlert = true
            return
        }
        if airPlay.needsAuthorizationValidation {
            pendingStartTime = requestedTime
            isPreparing = true
            status = "Comprobando autorización con el Apple TV…"
            detail = "La credencial se valida antes de preparar el VOD para evitar esperas y reintentos innecesarios."
            authorizationPreflight.start {
                try await self.airPlay.validateAuthorization()
            } onSuccess: { [weak self] in
                guard let self, self.selectedURL == selectedURL else { return }
                self.isPreparing = false
                self.continueStart(at: requestedTime)
            } onFailure: { [weak self] error in
                guard let self else { return }
                self.isPreparing = false
                if self.requestAuthorizationRenewalIfNeeded(error, retryAt: requestedTime) {
                    return
                }
                self.presentError(title: "No se pudo comprobar la autorización", detail: error.localizedDescription)
            }
            return
        }
        if airPlay.requiresPairing {
            requestAuthorizationRenewal(
                message: "El código se mostrará en el Apple TV y se introduce directamente aquí.",
                retryAt: requestedTime
            )
            return
        }
        if info.isHDR, selectedSubtitle != nil {
            if let storageError = Self.storagePreflightError(fileSize: info.fileSize, sizeMultiplier: 1.12) {
                presentError(title: "No hay espacio temporal suficiente", detail: storageError)
                return
            }
            beginDirectHDRSubtitleStreaming(url: selectedURL, info: info, requestedTime: requestedTime)
        } else {
            beginStreaming(url: selectedURL, info: info, requestedTime: requestedTime)
        }
    }

    func confirmAudioConversion(to mode: AudioOutputMode = .compatible, rememberForPlaylist: Bool = true) {
        guard mode == .compatible || (mode == .losslessFLAC && canOfferLosslessAudioConversion)
        else { return }
        showConversionAlert = false
        if rememberForPlaylist, let audio = selectedAudio {
            playlistAudioConsent.authorize(audio: audio, output: mode)
        } else {
            playlistAudioConsent.reset()
        }
        audioOutputMode = mode
        continueStart(at: pendingStartTime)
    }

    func cancelAudioConversion() {
        showConversionAlert = false
        playlistAudioConsent.reset()
        transitionPower.end()
        status = "Conversión cancelada"
        detail = "No se ha cambiado ni reproducido nada. Puedes elegir otra pista de audio."
    }

    func resolveRemoteConversion(decisionID: UUID, approve: Bool, equivalentEpisodes: Bool) -> Bool {
        guard showConversionAlert, remoteConversionDecisionID == decisionID,
            let expectedAudio = remoteConversionAudio, expectedAudio == selectedAudio
        else { return false }
        if approve {
            confirmAudioConversion(to: .compatible, rememberForPlaylist: equivalentEpisodes)
        } else {
            cancelAudioConversion()
        }
        return true
    }

    func applyTrackSettings() {
        if let subtitle = selectedSubtitle, let reason = subtitle.unsupportedReason {
            presentError(title: "Subtítulo no disponible todavía", detail: reason)
            return
        }
        if isStreaming || isPreparing {
            let target = moviePosition
            status = "Aplicando pistas…"
            detail = "Se preparará de nuevo la película completa y continuará desde el mismo punto."
            start(at: target)
        } else {
            hasError = false
            status = "Pistas preparadas"
            detail = "Los cambios se aplicarán al iniciar la reproducción."
        }
    }

    func togglePlayback() {
        guard commandAvailability.canTogglePlayback else { return }
        guard isStreaming else {
            start()
            return
        }
        if isPlaying {
            if airPlay.pause() {
                status = "Pausando en el Apple TV…"
                detail = "AirCiller actualizará el estado cuando el receptor confirme la pausa."
            }
        } else {
            if airPlay.resume() {
                status = "Reanudando en el Apple TV…"
                detail = "AirCiller actualizará el estado cuando el receptor confirme la reproducción."
            }
        }
    }

    func seek(to time: Double) {
        guard commandAvailability.canSeek, time.isFinite else { return }
        let target = min(max(time, 0), max(duration - 0.5, 0))
        currentTime = target
        if isStreaming {
            status = L10n.format("Saltando a %@…", TimeFormatting.duration(target))
            detail = "Moviéndome dentro de la película en el Apple TV."
            airPlay.seek(to: target)
        }
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func previousChapter() {
        guard commandAvailability.canChangeChapter else { return }
        let target = chapters.last(where: { $0.start < moviePosition - 3 })?.start ?? 0
        seek(to: presentationPosition(forMovie: target))
    }

    func nextChapter() {
        guard commandAvailability.canChangeChapter else { return }
        guard let target = chapters.first(where: { $0.start > moviePosition + 1 })?.start else { return }
        seek(to: presentationPosition(forMovie: target))
    }

    func stop(resetStatus: Bool = true, preservingPlaylist: Bool = false, preservingTransition: Bool = false) {
        remoteControlSessionID = UUID()
        remoteReceiverObservation = nil
        if !preservingPlaylist {
            playlistAudioConsent.reset()
            remoteSessionAudioLanguage = nil
            remoteSessionSubtitleLanguage = nil
        }
        if !preservingTransition { transitionPower.end() }
        saveCurrentPosition(force: true)
        activeAnalysisID = nil
        isAnalyzing = false
        automaticStartWait.cancel()
        mediaAnalysisTasks.cancelAll()
        streamTask?.cancel()
        streamTask = nil
        cancelAuthorizationPreflight()
        airPlay.cancelPairing()
        showConversionAlert = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        airPlay.stop(silently: true)
        cleanupRuntime()
        isPreparing = false
        isStreaming = false
        isPlaying = false
        preparationProgress = 0
        if resetStatus {
            hasError = false
            status = selectedURL == nil ? "Listo" : "Detenido"
            detail =
                selectedURL == nil
                ? "Elige una película y AirCiller comprobará todas sus pistas."
                : "No queda ningún proceso reproduciendo en segundo plano."
        }
    }

    func playQueueItem(_ item: QueueMediaItem) {
        guard libraryFileExists(item.url) else { return }
        loadVideo(item.url, autoStart: true)
    }

    func playQueueItemFromBeginning(_ item: QueueMediaItem) {
        guard libraryFileExists(item.url) else { return }
        loadVideo(item.url, autoStart: true, startingAt: 0)
    }

    func playRecentFromBeginning(_ item: RecentMediaItem) {
        guard libraryFileExists(item.url) else { return }
        loadVideo(item.url, autoStart: true, startingAt: 0)
    }

    func removeQueueItem(_ item: QueueMediaItem) {
        guard let removedIndex = queueItems.firstIndex(where: { $0.id == item.id }) else { return }
        let previousItems = queueItems
        let previousFocus = focusedQueueItemID
        queueItems.removeAll(where: { $0.id == item.id })
        if focusedQueueItemID == item.id {
            let replacementIndex = min(removedIndex, max(queueItems.count - 1, 0))
            focusedQueueItemID = queueItems.indices.contains(replacementIndex) ? queueItems[replacementIndex].id : nil
        }
        HistoryStore.saveQueue(queueItems)
        registerQueueUndo(before: previousItems, focus: previousFocus, actionName: "Quitar de la playlist")
        if let focusedQueueSeasonID, !queueItems.contains(where: { $0.seasonID == focusedQueueSeasonID }) {
            self.focusedQueueSeasonID = nil
        }
    }

    func setLibraryUndoManager(_ manager: UndoManager?) {
        guard libraryUndoManager !== manager else { return }
        libraryUndoManager?.removeAllActions(withTarget: self)
        libraryUndoManager = manager
    }

    private func registerQueueUndo(before items: [QueueMediaItem], focus: String?, actionName: String) {
        guard let edit = LibraryListUndo(before: items, after: queueItems) else { return }
        registerQueueUndo(edit, focus: focus, seasonFocus: focusedQueueSeasonID, actionName: actionName)
    }

    private func registerQueueUndo(
        _ edit: LibraryListUndo<QueueMediaItem>, focus: String?, seasonFocus: String?, actionName: String
    ) {
        libraryUndoManager?.registerUndo(withTarget: self) { coordinator in
            MainActor.assumeIsolated {
                coordinator.applyQueueUndo(edit, focus: focus, seasonFocus: seasonFocus, actionName: actionName)
            }
        }
        libraryUndoManager?.setActionName(L10n.text(actionName))
    }

    private func applyQueueUndo(
        _ edit: LibraryListUndo<QueueMediaItem>, focus: String?, seasonFocus: String?, actionName: String
    ) {
        registerQueueUndo(
            edit.inverse(in: queueItems), focus: focusedQueueItemID,
            seasonFocus: focusedQueueSeasonID, actionName: actionName)
        queueItems = edit.applying(to: queueItems)
        focusedQueueItemID = focus.flatMap { id in queueItems.contains { $0.id == id } ? id : nil }
        focusedQueueSeasonID = seasonFocus.flatMap { id in queueItems.contains { $0.seasonID == id } ? id : nil }
        HistoryStore.saveQueue(queueItems)
    }

    private func registerRecentUndo(before items: [RecentMediaItem], focus: String?, actionName: String) {
        guard let edit = LibraryListUndo(before: items, after: recentItems) else { return }
        registerRecentUndo(edit, focus: focus, actionName: actionName)
    }

    private func registerRecentUndo(_ edit: LibraryListUndo<RecentMediaItem>, focus: String?, actionName: String) {
        libraryUndoManager?.registerUndo(withTarget: self) { coordinator in
            MainActor.assumeIsolated {
                coordinator.applyRecentUndo(edit, focus: focus, actionName: actionName)
            }
        }
        libraryUndoManager?.setActionName(L10n.text(actionName))
    }

    private func applyRecentUndo(_ edit: LibraryListUndo<RecentMediaItem>, focus: String?, actionName: String) {
        registerRecentUndo(edit.inverse(in: recentItems), focus: focusedRecentItemID, actionName: actionName)
        recentItems = edit.applying(to: recentItems, maximumCount: HistoryStore.maximumRecentItems)
        focusedRecentItemID = focus.flatMap { id in recentItems.contains { $0.id == id } ? id : nil }
        HistoryStore.saveRecent(recentItems)
    }

    func focusQueueItem(_ item: QueueMediaItem) {
        guard queueItems.contains(where: { $0.id == item.id }) else { return }
        focusedQueueItemID = item.id
        focusedQueueSeasonID = nil
    }

    func focusQueueSeason(_ id: String) {
        guard seasonFolders.contains(where: { $0.id == id }), queueItems.contains(where: { $0.seasonID == id }) else {
            return
        }
        focusedQueueItemID = nil
        focusedQueueSeasonID = id
    }

    func clearQueueFocus() {
        focusedQueueItemID = nil
        focusedQueueSeasonID = nil
    }

    private var focusedSeasonRoot: (index: Int, items: [QueueMediaItem])? {
        guard let focusedQueueSeasonID else { return nil }
        var seen = Set<String>()
        let roots = queueItems.filter { item in
            guard let season = item.seasonID else { return true }
            return seen.insert(season).inserted
        }
        guard let index = roots.firstIndex(where: { $0.seasonID == focusedQueueSeasonID }) else { return nil }
        return (index, roots)
    }

    var canMoveFocusedQueueItemUp: Bool {
        if let root = focusedSeasonRoot { return root.index > 0 }
        guard let focusedQueueItemID,
            let index = queueItems.firstIndex(where: { $0.id == focusedQueueItemID })
        else {
            return false
        }
        if let season = queueItems[index].seasonID {
            return queueItems.first(where: { $0.seasonID == season })?.id != focusedQueueItemID
        }
        return index > queueItems.startIndex
    }

    var canMoveFocusedQueueItemDown: Bool {
        if let root = focusedSeasonRoot { return root.index + 1 < root.items.count }
        guard let focusedQueueItemID,
            let index = queueItems.firstIndex(where: { $0.id == focusedQueueItemID })
        else {
            return false
        }
        if let season = queueItems[index].seasonID {
            return queueItems.last(where: { $0.seasonID == season })?.id != focusedQueueItemID
        }
        return index < queueItems.index(before: queueItems.endIndex)
    }

    @discardableResult
    func moveFocusedQueueItem(by offset: Int) -> Bool {
        if let root = focusedSeasonRoot, let season = focusedQueueSeasonID {
            guard offset != 0 else { return false }
            let destination = min(max(root.index + offset, 0), root.items.count - 1)
            guard destination != root.index else { return false }
            let beforeIndex = offset > 0 ? destination + 1 : destination
            let before = beforeIndex < root.items.count ? root.items[beforeIndex].id : nil
            moveQueueItems(ids: queueItems.filter { $0.seasonID == season }.map(\.id), before: before)
            return true
        }
        guard let focusedQueueItemID,
            let reordered = QueueOrdering.movingItem(queueItems, id: focusedQueueItemID, by: offset)
        else {
            return false
        }
        if let item = queueItems.first(where: { $0.id == focusedQueueItemID }), let group = item.seasonID {
            let siblings = queueItems.filter { $0.seasonID == group }
            guard let moved = QueueOrdering.movingItem(siblings, id: item.id, by: offset) else { return false }
            let previousItems = queueItems
            var iterator = moved.makeIterator()
            for index in queueItems.indices where queueItems[index].seasonID == group {
                if let next = iterator.next() { queueItems[index] = next }
            }
            HistoryStore.saveQueue(queueItems)
            registerQueueUndo(before: previousItems, focus: focusedQueueItemID, actionName: "Ordenar la playlist")
            return true
        }
        if queueItems.contains(where: { $0.seasonID != nil }) {
            var seen = Set<String>()
            let roots = queueItems.filter { item in
                guard let group = item.seasonID else { return true }
                return seen.insert(group).inserted
            }
            guard let index = roots.firstIndex(where: { $0.id == focusedQueueItemID }) else { return false }
            let destination = min(max(index + offset, 0), roots.count - 1)
            guard destination != index else { return false }
            let beforeIndex = offset > 0 ? destination + 1 : destination
            let before = beforeIndex < roots.count ? roots[beforeIndex].id : nil
            moveQueueItems(ids: [focusedQueueItemID], before: before)
            return true
        }
        let previousItems = queueItems
        queueItems = reordered
        HistoryStore.saveQueue(queueItems)
        registerQueueUndo(before: previousItems, focus: focusedQueueItemID, actionName: "Ordenar la playlist")
        return true
    }

    func moveQueueItems(fromOffsets: IndexSet, toOffset: Int) {
        let previousItems = queueItems
        queueItems = QueueOrdering.moving(queueItems, fromOffsets: fromOffsets, toOffset: toOffset)
        normalizeSeasonOrder()
        HistoryStore.saveQueue(queueItems)
        registerQueueUndo(before: previousItems, focus: focusedQueueItemID, actionName: "Ordenar la playlist")
    }

    func moveQueueItems(ids: [String], before destinationID: String?) {
        let offsets = IndexSet(
            ids.compactMap { id in
                queueItems.firstIndex(where: { $0.id == id })
            })
        let destination =
            destinationID.flatMap { id in
                queueItems.firstIndex(where: { $0.id == id })
            } ?? queueItems.endIndex
        moveQueueItems(fromOffsets: offsets, toOffset: destination)
    }

    func clearQueue() {
        playlistAudioConsent.reset()
        let previousItems = queueItems
        let previousFocus = focusedQueueItemID
        queueItems.removeAll()
        focusedQueueItemID = nil
        HistoryStore.saveQueue(queueItems)
        registerQueueUndo(before: previousItems, focus: previousFocus, actionName: "Vaciar la playlist")
        focusedQueueSeasonID = nil
    }

    func removeRecent(_ item: RecentMediaItem) {
        guard let removedIndex = recentItems.firstIndex(where: { $0.id == item.id }) else { return }
        let previousItems = recentItems
        let previousFocus = focusedRecentItemID
        recentItems.removeAll(where: { $0.id == item.id })
        if focusedRecentItemID == item.id {
            let replacementIndex = min(removedIndex, max(recentItems.count - 1, 0))
            focusedRecentItemID =
                recentItems.indices.contains(replacementIndex) ? recentItems[replacementIndex].id : nil
        }
        HistoryStore.saveRecent(recentItems)
        registerRecentUndo(before: previousItems, focus: previousFocus, actionName: "Quitar de Recientes")
    }

    func clearRecent() {
        let previousItems = recentItems
        let previousFocus = focusedRecentItemID
        recentItems.removeAll()
        focusedRecentItemID = nil
        HistoryStore.saveRecent(recentItems)
        registerRecentUndo(before: previousItems, focus: previousFocus, actionName: "Borrar historial")
    }

    private func libraryFileExists(_ url: URL, offerToLocate: Bool = true) -> Bool {
        guard HistoryStore.isAvailable(url) else {
            unavailableLibraryPaths.insert(url.path)
            if offerToLocate {
                let alert = NSAlert()
                alert.messageText = L10n.text("Archivo no disponible")
                alert.informativeText = L10n.format(
                    "No se puede abrir %@. Conecta el disco o localiza el archivo. Se conservan su lugar en la biblioteca y el progreso guardado.",
                    url.lastPathComponent)
                alert.addButton(withTitle: L10n.text("Cancelar"))
                alert.addButton(withTitle: L10n.text("Localizar archivo…"))
                if alert.runModal() == .alertSecondButtonReturn { locateLibraryFile(url) }
            } else {
                presentError(
                    title: "Archivo no disponible",
                    detail:
                        "La siguiente película no está disponible. Conecta el disco o localiza el archivo desde la biblioteca."
                )
            }
            return false
        }
        unavailableLibraryPaths.remove(url.path)
        return true
    }

    func locateLibraryFile(_ oldURL: URL) {
        guard !(selectedURL?.path == oldURL.path && (isPreparing || isStreaming)) else {
            let alert = NSAlert()
            alert.messageText = L10n.text("Detén esta película antes de localizar su archivo")
            alert.runModal()
            return
        }
        let panel = NSOpenPanel()
        panel.title = L10n.text("Localizar archivo…")
        panel.message = L10n.text(
            "Elige la misma película. Se conservarán el orden y el progreso; no empezará a reproducirse.")
        panel.prompt = L10n.text("Localizar")
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = MediaFileTypes.contentTypes
        guard panel.runModal() == .OK, let newURL = panel.url,
            MediaFileTypes.accepts(newURL),
            HistoryStore.isAvailable(newURL),
            !(selectedURL?.path == oldURL.path && (isPreparing || isStreaming))
        else { return }
        guard let relocated = HistoryStore.relocating(from: oldURL, to: newURL, recent: recentItems, queue: queueItems)
        else {
            let alert = NSAlert()
            alert.messageText = L10n.text("No se ha cambiado la biblioteca")
            alert.informativeText = L10n.text(
                "El destino ya está en la biblioteca o la entrada original ha cambiado. No se ha combinado ni eliminado ninguna entrada."
            )
            alert.runModal()
            return
        }
        // Relinking changes entry identity; an older Undo must not resurrect the obsolete path.
        if oldURL.path != newURL.path { libraryUndoManager?.removeAllActions(withTarget: self) }
        recentItems = relocated.recent
        queueItems = relocated.queue
        if focusedQueueItemID == oldURL.path { focusedQueueItemID = newURL.path }
        if focusedRecentItemID == oldURL.path { focusedRecentItemID = newURL.path }
        unavailableLibraryPaths.remove(oldURL.path)
        unavailableLibraryPaths.remove(newURL.path)
        HistoryStore.saveRecent(recentItems)
        HistoryStore.saveQueue(queueItems)
        if selectedURL?.path == oldURL.path {
            // Re-probe the explicit replacement without saving the old path back into history.
            selectedURL = newURL
            loadVideo(newURL, autoStart: false)
        }
    }

    private func reportOCRProgress(
        completed: Int,
        total: Int,
        sessionID: UUID,
        baseProgress: Double,
        span: Double
    ) {
        guard activeSessionID == sessionID, total > 0 else { return }
        let boundedCompleted = min(max(completed, 0), total)
        let fraction = Double(boundedCompleted) / Double(total)
        preparationProgress = baseProgress + (span * fraction)
        status = L10n.format(
            "Leyendo subtítulos gráficos… %lld/%lld", Int64(boundedCompleted), Int64(total))
        detail =
            boundedCompleted == total
            ? "OCR local terminado. Creando la pista WebVTT seleccionable."
            : "Apple Vision está reconociendo la pista gráfica localmente."
    }

    private func prepareStreamSession(
        requestedTime: Double,
        duration: Double,
        status preparationStatus: String,
        detail preparationDetail: String
    ) -> (id: UUID, startTime: Double) {
        streamTask?.cancel()
        player.pause()
        player.replaceCurrentItem(with: nil)
        airPlay.stop(silently: true)
        cleanupRuntime()
        resetStreamSessionMetrics()

        let sessionID = UUID()
        activeSessionID = sessionID
        playbackPower.begin()
        transitionPower.end()
        let startTime = min(max(requestedTime, 0), max(duration - 0.5, 0))
        currentTime = startTime
        isPreparing = true
        isStreaming = false
        isPlaying = false
        hasError = false
        preparationProgress = 0
        status = L10n.text(preparationStatus)
        detail = L10n.text(preparationDetail)
        return (sessionID, startTime)
    }

    private func beginDirectHDRSubtitleStreaming(url: URL, info: MediaProbe, requestedTime: Double) {
        // Capture ownership before suspending. A new selection may start its own
        // analysis while this session waits for the old ffprobe process to exit.
        let cancelledDemand = mediaAnalysisTasks.cancelDemand()
        let session = prepareStreamSession(
            requestedTime: requestedTime,
            duration: info.duration,
            status: "Preparando HDR con subtítulos…",
            detail: "Creando un MP4 de inicio rápido con el vídeo intacto y la pista de texto elegida."
        )
        let sessionID = session.id
        let startTime = session.startTime

        let audio = selectedAudio
        let subtitle = selectedSubtitle
        let outputMode = audioOutputMode
        let chosenAudioDelay = audioDelay
        let chosenSubtitleDelay = subtitleDelay

        streamTask = Task { [weak self] in
            guard let self else { return }
            var sessionDirectory: URL?
            var sessionServer: LocalHTTPServer?
            var sessionProcess: Process?
            do {
                await cancelledDemand?.value
                try Task.checkCancellation()
                guard self.activeSessionID == sessionID else { throw CancellationError() }
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("AirCiller-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                sessionDirectory = directory
                guard self.activeSessionID == sessionID else { throw CancellationError() }
                self.temporaryDirectory = directory

                var preparedSubtitle = subtitle
                if let subtitle, subtitle.usesBitmapOCR {
                    self.status = "Leyendo subtítulos gráficos…"
                    self.detail =
                        "Apple Vision reconoce la pista gráfica localmente. La película y el vídeo HDR permanecen intactos."
                    self.preparationProgress = 0.04
                    preparedSubtitle = try await SubtitleService.materializeDirectTrack(
                        subtitle,
                        videoURL: url,
                        videoDuration: info.duration,
                        outputDirectory: directory,
                        ocrProgress: { [weak self] completed, total in
                            Task { @MainActor [weak self] in
                                self?.reportOCRProgress(
                                    completed: completed,
                                    total: total,
                                    sessionID: sessionID,
                                    baseProgress: 0.04,
                                    span: 0.06
                                )
                            }
                        }
                    )
                    try Task.checkCancellation()
                    guard self.activeSessionID == sessionID else { throw CancellationError() }
                }

                let outputURL = directory.appendingPathComponent("movie.mp4")
                let build = try Self.makeDirectFileProcess(
                    input: url,
                    output: outputURL,
                    probe: info,
                    audio: audio,
                    outputMode: outputMode,
                    audioDelay: chosenAudioDelay,
                    subtitle: preparedSubtitle,
                    subtitleDelay: chosenSubtitleDelay
                )
                let process = build.process
                sessionProcess = process
                self.ffmpegProcess = process
                self.ffmpegLog = build.log
                try process.run()
                build.didStart()
                let exitTask = Task {
                    try await CancellableProcess(process).waitForExit()
                }
                try await self.waitForVODCompletion(
                    build,
                    exitTask: exitTask,
                    expectedDuration: info.duration,
                    sessionID: sessionID,
                    preparationName: "MP4 HDR con subtítulos"
                )
                build.closePipes()
                try self.requireCurrentStreamSession(sessionID)
                if self.activeSessionID == sessionID {
                    self.ffmpegProcess = nil
                    self.ffmpegLog = nil
                }

                self.status = "Ajustando la cabecera HDR…"
                self.detail = "Conservando Dolby Vision/HDR y colocando la duración y el índice al principio del MP4."
                self.preparationProgress = 0.93
                let isHDR10CompatibleDolbyVision = info.dolbyVisionProfile == 8 && info.dolbyVisionCompatibilityID == 1
                if info.colorTransfer?.lowercased() == "smpte2084"
                    && (!info.isDolbyVision || isHDR10CompatibleDolbyVision)
                {
                    try HDRConfigurationInjector.injectStaticMetadataIntoDirectFile(outputURL)
                }

                self.status = "Comprobando HDR y subtítulos…"
                self.detail = "Verificando duración, vídeo, audio y pista de texto dentro del MP4."
                self.preparationProgress = 0.96
                let prepared = try await MediaProbeService.probe(url: outputURL)
                try self.requireCurrentStreamSession(sessionID)
                if info.isDolbyVision, !prepared.isDolbyVision {
                    throw AirCillerError.invalidVODPackage(
                        "El MP4 preparado no conserva los metadatos Dolby Vision."
                    )
                }
                if !info.isDolbyVision, info.isHDR, !prepared.isHDR {
                    throw AirCillerError.invalidVODPackage(
                        "El MP4 preparado no conserva los metadatos HDR."
                    )
                }
                guard abs(prepared.duration - info.duration) <= max(15, info.duration * 0.002) else {
                    throw AirCillerError.invalidVODPackage(
                        L10n.format(
                            "El MP4 preparado dura %@, no %@.",
                            TimeFormatting.duration(prepared.duration),
                            TimeFormatting.duration(info.duration))
                    )
                }
                if audio != nil, prepared.audioTracks.isEmpty {
                    throw AirCillerError.invalidVODPackage("El MP4 preparado no contiene la pista de audio elegida.")
                }
                if subtitle != nil, prepared.subtitleTracks.isEmpty {
                    throw AirCillerError.invalidVODPackage(
                        "El MP4 preparado no contiene el subtítulo elegible en Apple TV.")
                }
                self.packagedDemandProfile = try StreamDemandAnalyzer.directFileProfile(
                    fileURL: outputURL,
                    duration: prepared.duration,
                    peakRatio: self.streamDemandProfile?.variabilityRatio
                )

                let localServer = self.makeLocalServer(
                    rootDirectory: directory,
                    sessionID: sessionID
                )
                sessionServer = localServer
                self.server = localServer
                let baseURL = try await localServer.start()
                let playbackURL = baseURL.appendingPathComponent("movie.mp4")
                try Task.checkCancellation()
                guard self.activeSessionID == sessionID else { throw CancellationError() }

                let item = AVPlayerItem(url: playbackURL)
                item.preferredForwardBufferDuration = 12
                let isPlayable = try await item.asset.load(.isPlayable)
                try self.requireCurrentStreamSession(sessionID)
                guard isPlayable else {
                    throw AirCillerError.invalidVODPackage("AVPlayer no reconoce el MP4 HDR como reproducible.")
                }
                let playerDuration = try await item.asset.load(.duration).seconds
                try self.requireCurrentStreamSession(sessionID)
                guard playerDuration.isFinite,
                    abs(playerDuration - prepared.duration) <= max(2.5, info.duration * 0.002)
                else {
                    throw AirCillerError.invalidVODPackage("AVPlayer no recibe la duración completa del MP4.")
                }
                if subtitle != nil {
                    guard let group = try await item.asset.loadMediaSelectionGroup(for: .legible),
                        let option = group.options.first
                    else {
                        throw AirCillerError.invalidVODPackage("AVPlayer no encuentra el subtítulo dentro del MP4.")
                    }
                    try self.requireCurrentStreamSession(sessionID)
                    item.select(option, in: group)
                }
                self.observe(item: item)
                self.player.replaceCurrentItem(with: item)
                let playableStartTime = min(startTime, max(0, prepared.duration - 0.5))
                self.currentTime = playableStartTime
                if playableStartTime > 0.05 { await self.seekPlayer(to: playableStartTime) }
                try self.requireCurrentStreamSession(sessionID)
                self.player.pause()

                self.status = L10n.format(
                    "Conectando con %@…", self.airPlay.selectedDevice?.name ?? "Apple TV")
                self.detail = "Enviando HDR y la pista de subtítulos integrada por AirPlay 2."
                try await self.airPlay.startPlayback(
                    url: playbackURL,
                    position: playableStartTime,
                    duration: prepared.duration,
                    title: self.selectedURL?.deletingPathExtension().lastPathComponent
                )
                try self.requireCurrentStreamSession(sessionID)
                self.status = "Confirmando el stream en el Apple TV…"
                self.detail = "Esperando la primera petición real de vídeo del receptor."
                try await self.waitForReceiverMediaRequest(sessionID: sessionID)
                try self.requireCurrentStreamSession(sessionID)
                self.authorizationRetryPolicy.reset()

                self.duration = prepared.duration
                self.isPreparing = false
                self.isStreaming = true
                self.isPlaying = true
                self.preparationProgress = 1
                self.status = L10n.format(
                    "Reproduciendo en %@", self.airPlay.selectedDevice?.name ?? "Apple TV")
                self.detail = L10n.format(
                    "HDR/Dolby Vision · %@ · vídeo intacto · subtítulos integrados.",
                    TimeFormatting.duration(prepared.duration))
            } catch is CancellationError {
                Self.cleanupLocalResources(process: sessionProcess, server: sessionServer, directory: sessionDirectory)
            } catch {
                if self.activeSessionID == sessionID {
                    self.cleanupRuntime()
                } else {
                    Self.cleanupLocalResources(
                        process: sessionProcess, server: sessionServer, directory: sessionDirectory)
                    return
                }
                self.isPreparing = false
                self.isStreaming = false
                self.isPlaying = false
                self.preparationProgress = 0
                if self.requestAuthorizationRenewalIfNeeded(error, retryAt: startTime) {
                    return
                }
                self.presentError(title: "No se pudo iniciar HDR con subtítulos", detail: error.localizedDescription)
            }
        }
    }

    /// Asset loads and seeks can finish after Stop or a replacement movie.
    /// Revalidate ownership before touching the shared player or its observers.
    private func requireCurrentStreamSession(_ sessionID: UUID) throws {
        try Task.checkCancellation()
        guard activeSessionID == sessionID else { throw CancellationError() }
    }

    private func beginStreaming(url: URL, info: MediaProbe, requestedTime: Double) {
        let session = prepareStreamSession(
            requestedTime: requestedTime,
            duration: info.duration,
            status: "Preparando la película completa…",
            detail: "Creando un VOD local con duración final. El vídeo original permanece intacto."
        )
        let sessionID = session.id
        let startTime = session.startTime
        // Segment sizes provide the final HLS demand profile. Do not compete
        // with remuxing by scanning every source packet at the same time.
        mediaAnalysisTasks.cancelDemand()
        startupTrace = PlaybackStartupTrace(sessionID: sessionID)
        startupSpans.removeAll()
        startupUsedCache = false

        let audio = selectedAudio
        let subtitle = selectedSubtitle
        let outputMode = audioOutputMode
        let chosenAudioDelay = audioDelay
        let chosenSubtitleDelay = subtitleDelay
        let usesDirectHDRRendition = info.isHDR

        streamTask = Task { [weak self] in
            guard let self else { return }
            var sessionDirectory: URL?
            var sessionServer: LocalHTTPServer?
            do {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("AirCiller-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                sessionDirectory = directory
                guard self.activeSessionID == sessionID else { throw CancellationError() }
                self.temporaryDirectory = directory

                self.preparingHLSDirectory = directory
                guard let ffmpegURL = Executables.find("ffmpeg") else { throw AirCillerError.ffmpegMissing }
                #if AIRCILLER_PLAYBACK_CHECKS
                    let cache: PreparedMediaCache? = self.playbackCheckPreparedMediaCache
                #else
                    let cache: PreparedMediaCache? = AirCillerStorage.preparedMediaCache
                    _ = try? await cache?.setLimitBytes(AirCillerStorage.preparedMediaCacheLimitBytes)
                #endif
                let prepared = try await HLSPreparationService.prepare(
                    input: url, probe: info, audio: audio, outputMode: outputMode,
                    audioDelay: chosenAudioDelay, subtitle: subtitle, subtitleDelay: chosenSubtitleDelay,
                    outputDirectory: directory, ffmpegURL: ffmpegURL, cache: cache,
                    observer: { [weak self] event in
                        self?.handleHLSPreparation(event, sessionID: sessionID, expectedDuration: info.duration)
                    }
                )
                try Task.checkCancellation()
                guard self.activeSessionID == sessionID else { throw CancellationError() }
                self.preparingHLSDirectory = nil
                let packagedDuration = prepared.duration
                self.packagedDemandProfile = prepared.demandProfile

                self.beginStartupStage(.localServer, sessionID: sessionID)
                let localServer = self.makeLocalServer(
                    rootDirectory: directory,
                    sessionID: sessionID
                )
                sessionServer = localServer
                self.server = localServer
                let baseURL = try await localServer.start()
                self.endStartupStage(.localServer, sessionID: sessionID)
                self.beginStartupStage(.localAsset, sessionID: sessionID)
                try Task.checkCancellation()
                guard self.activeSessionID == sessionID else { throw CancellationError() }

                let playbackFile = usesDirectHDRRendition ? "video.m3u8" : "master.m3u8"
                let playbackURL = baseURL.appendingPathComponent(playbackFile)
                let item = AVPlayerItem(url: playbackURL)
                item.preferredForwardBufferDuration = 12
                let isPlayable = try await item.asset.load(.isPlayable)
                try Task.checkCancellation()
                guard self.activeSessionID == sessionID else { throw CancellationError() }
                guard isPlayable else {
                    throw AirCillerError.invalidVODPackage("AVPlayer no reconoce el paquete como reproducible.")
                }
                let playerDuration = try await item.asset.load(.duration).seconds
                try Task.checkCancellation()
                guard self.activeSessionID == sessionID else { throw CancellationError() }
                guard playerDuration.isFinite, playerDuration > 0 else {
                    throw AirCillerError.invalidVODPackage("AVPlayer no ha recibido una duración final válida.")
                }
                guard abs(playerDuration - packagedDuration) <= max(2.5, info.duration * 0.002) else {
                    throw AirCillerError.invalidVODPackage(
                        L10n.format(
                            "AVPlayer recibe %@, no la duración completa del archivo.",
                            TimeFormatting.duration(playerDuration))
                    )
                }
                if subtitle != nil {
                    guard let group = try await item.asset.loadMediaSelectionGroup(for: .legible),
                        let option = group.options.first
                    else {
                        throw AirCillerError.invalidVODPackage(
                            "AVPlayer no encuentra la pista de subtítulos WebVTT preparada."
                        )
                    }
                    try Task.checkCancellation()
                    guard self.activeSessionID == sessionID else { throw CancellationError() }
                    item.select(option, in: group)
                }
                self.observe(item: item)
                self.player.replaceCurrentItem(with: item)
                let timelineInfo = try HLSAudioTimelineInfo.load(directory: directory)
                self.activeMovieTimeline = timelineInfo.map {
                    MoviePlaybackTimeline(
                        sourceDuration: $0.sourceDuration, presentationDuration: $0.presentationDuration,
                        videoContentOffset: $0.videoContentOffset)
                }
                let playableStartTime = min(
                    self.presentationPosition(forMovie: startTime), max(0, packagedDuration - 0.5))
                self.currentTime = playableStartTime
                if playableStartTime > 0.05 {
                    await self.seekPlayer(to: playableStartTime)
                }
                try Task.checkCancellation()
                guard self.activeSessionID == sessionID else { throw CancellationError() }
                self.player.pause()

                self.endStartupStage(.localAsset, sessionID: sessionID)
                self.beginStartupStage(.airPlay, sessionID: sessionID)
                self.status = L10n.format(
                    "Conectando con %@…", self.airPlay.selectedDevice?.name ?? "Apple TV")
                self.detail = "Enviando la orden directamente por AirPlay y esperando confirmación real de duración."
                try await self.airPlay.startPlayback(
                    url: playbackURL,
                    position: playableStartTime,
                    duration: packagedDuration,
                    title: self.selectedURL?.deletingPathExtension().lastPathComponent
                )
                self.endStartupStage(.airPlay, sessionID: sessionID)
                try Task.checkCancellation()
                guard self.activeSessionID == sessionID else { throw CancellationError() }
                self.beginStartupStage(.receiverRequest, sessionID: sessionID)
                self.status = "Confirmando el stream en el Apple TV…"
                self.detail = "Esperando la primera petición real de vídeo del receptor."
                try await self.waitForReceiverMediaRequest(sessionID: sessionID)
                self.endStartupStage(.receiverRequest, sessionID: sessionID)
                self.startupTrace?.finish(.receiverMediaRequest, sessionID: sessionID)
                self.authorizationRetryPolicy.reset()

                self.duration = packagedDuration
                self.isPreparing = false
                self.isStreaming = true
                self.isPlaying = true
                self.preparationProgress = 1
                self.status = L10n.format(
                    "Reproduciendo en %@", self.airPlay.selectedDevice?.name ?? "Apple TV")
                self.detail =
                    outputMode == .losslessFLAC
                    ? L10n.format(
                        "VOD completo · %@ · vídeo intacto · audio convertido a FLAC sin pérdida.",
                        TimeFormatting.duration(packagedDuration))
                    : usesDirectHDRRendition
                        ? (subtitle == nil
                            ? L10n.format(
                                "HDR/Dolby Vision · %@ · vídeo y audio intactos.",
                                TimeFormatting.duration(packagedDuration))
                            : L10n.format(
                                "HDR/Dolby Vision · %@ · vídeo y audio intactos · subtítulos WebVTT.",
                                TimeFormatting.duration(packagedDuration)))
                        : L10n.format(
                            "VOD completo · %@ · control AirPlay directo.",
                            TimeFormatting.duration(packagedDuration))
            } catch is CancellationError {
                self.startupTrace?.finish(.cancelled, sessionID: sessionID)
                if self.preparingHLSDirectory == sessionDirectory { self.preparingHLSDirectory = nil }
                Self.cleanupLocalResources(
                    process: nil,
                    server: sessionServer,
                    directory: sessionDirectory
                )
                return
            } catch {
                self.startupTrace?.finish(.failed, sessionID: sessionID)
                if self.preparingHLSDirectory == sessionDirectory { self.preparingHLSDirectory = nil }
                if self.activeSessionID == sessionID {
                    self.cleanupRuntime()
                } else {
                    Self.cleanupLocalResources(
                        process: nil,
                        server: sessionServer,
                        directory: sessionDirectory
                    )
                    return
                }
                self.isPreparing = false
                self.isStreaming = false
                self.isPlaying = false
                self.preparationProgress = 0
                if self.requestAuthorizationRenewalIfNeeded(error, retryAt: startTime) {
                    return
                }
                self.presentError(title: "No se pudo iniciar la reproducción", detail: error.localizedDescription)
            }
        }
    }

    private func beginStartupStage(_ stage: PlaybackStartupTrace.Stage, sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        startupSpans[stage] = startupTrace?.begin(stage, sessionID: sessionID)
    }

    private func endStartupStage(_ stage: PlaybackStartupTrace.Stage, sessionID: UUID) {
        guard activeSessionID == sessionID else { return }
        startupTrace?.end(startupSpans.removeValue(forKey: stage), sessionID: sessionID)
    }

    private func handleHLSPreparation(
        _ event: HLSPreparationEvent, sessionID: UUID, expectedDuration: Double
    ) {
        guard activeSessionID == sessionID else { return }
        switch event {
        case .began(let stage):
            beginStartupStage(stage, sessionID: sessionID)
            if stage == .validation {
                status = "Comprobando la película preparada…"
                detail = "Verificando duración, cierre VOD y sincronía de todas las listas."
                preparationProgress = 0.96
            } else if stage == .subtitles, selectedSubtitle?.usesBitmapOCR == true {
                status = "Leyendo subtítulos gráficos…"
                detail = "Apple Vision reconoce la pista gráfica localmente y la convierte en WebVTT seleccionable."
                preparationProgress = 0.91
            }
        case .ended(let stage):
            endStartupStage(stage, sessionID: sessionID)
            if stage == .packaging {
                preparationProgress = 0.90
                if let selectedSubtitle, !selectedSubtitle.usesBitmapOCR {
                    status = "Alineando subtítulos…"
                    detail = "Creando una pista WebVTT para cada tramo de la película."
                }
            }
        case .packagingProgress(let seconds, let speed):
            let fraction = expectedDuration > 0 ? seconds / expectedDuration : 0
            preparationProgress = min(0.88, max(0.01, fraction * 0.88))
            status = L10n.format("Preparando %@…", L10n.text("VOD completo"))
            let percent = Int((preparationProgress / 0.88 * 100).rounded())
            if let speed, speed > 0.01 {
                detail = L10n.format(
                    "%lld %% · %@ · quedan aprox. %@ · vídeo intacto.",
                    Int64(percent), String(format: "%.1f×", speed),
                    TimeFormatting.duration(max(0, expectedDuration - seconds) / speed))
            } else {
                detail = L10n.format("%lld %% · sin recodificar el vídeo.", Int64(percent))
            }
        case .ocrProgress(let completed, let total):
            reportOCRProgress(completed: completed, total: total, sessionID: sessionID, baseProgress: 0.91, span: 0.04)
        case .process(let build):
            ffmpegProcess = build?.process
            ffmpegLog = build?.log
        case .cacheHit:
            startupUsedCache = true
        }
    }

    private func seekPlayer(to seconds: Double) async {
        await withCheckedContinuation { continuation in
            player.seek(
                to: CMTime(seconds: seconds, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            ) { _ in
                continuation.resume()
            }
        }
    }

    private func observe(item: AVPlayerItem) {
        clearItemObservers()
        let sessionID = activeSessionID
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in
                guard let self, self.activeSessionID == sessionID, self.player.currentItem === item else { return }
                self.presentPlaybackFailure(item.error)
            }
        }
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.activeSessionID == sessionID, self.player.currentItem === item else { return }
                self.playbackFinished()
            }
        }
        itemErrorObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewErrorLogEntry,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.activeSessionID == sessionID, self.player.currentItem === item else { return }
                self.recordErrorLog(for: item)
                if let error = item.error {
                    self.presentPlaybackFailure(error)
                }
            }
        }
    }

    private func recordErrorLog(for item: AVPlayerItem) {
        guard let event = item.errorLog()?.events.last else {
            playbackLogger.error("AVPlayer notificó un error sin entrada de diagnóstico")
            return
        }
        playbackLogger.error(
            "AVPlayer status=\(event.errorStatusCode, privacy: .public) domain=\(event.errorDomain, privacy: .public) comment=\(event.errorComment ?? "-", privacy: .private) uri=\(event.uri ?? "-", privacy: .private)"
        )
    }

    private func presentPlaybackFailure(_ error: Error?) {
        playbackLogger.error("Fallo de reproducción: \(error?.localizedDescription ?? "sin motivo", privacy: .private)")
        hasError = true
        status =
            player.isExternalPlaybackActive
            ? "Apple TV rechazó la reproducción"
            : "No se pudo reproducir la película"
        let raw = error?.localizedDescription ?? "El dispositivo no ha indicado el motivo exacto."
        if raw.localizedCaseInsensitiveContains("format") || raw.localizedCaseInsensitiveContains("codec") {
            detail = L10n.format("La pista elegida no es compatible con el dispositivo. %@", raw)
        } else if raw.localizedCaseInsensitiveContains("network") || raw.localizedCaseInsensitiveContains("server") {
            detail = L10n.format(
                "Se perdió la conexión local. Comprueba que el Mac y el Apple TV sigan en la misma red. %@",
                raw)
        } else {
            detail = L10n.format("Motivo comunicado por el reproductor: %@", raw)
        }
    }

    private func playbackFinished() {
        guard activeSessionID != nil else { return }
        currentTime = duration
        saveCurrentPosition(force: true)
        if let selectedURL, let index = queueItems.firstIndex(where: { $0.path == selectedURL.path }) {
            queueItems[index].watched = true
            HistoryStore.saveQueue(queueItems)
        }
        transitionPower.begin()
        cleanupRuntime()
        isStreaming = false
        isPlaying = false
        if let selectedURL,
            let currentIndex = queueItems.firstIndex(where: { $0.path == selectedURL.path }),
            queueItems.indices.contains(currentIndex + 1)
        {
            let next = queueItems[currentIndex + 1]
            guard libraryFileExists(next.url, offerToLocate: false) else {
                transitionPower.end()
                playlistAudioConsent.reset()
                return
            }
            loadVideo(next.url, autoStart: true, continuingPlaylist: true)
        } else {
            transitionPower.end()
            playlistAudioConsent.reset()
            status = "Reproducción terminada"
            detail = "No hay otro título después en la playlist."
        }
    }

    private func playbackStoppedByReceiver() {
        playlistAudioConsent.reset()
        transitionPower.end()
        saveCurrentPosition(force: true)
        cleanupRuntime()
        isPreparing = false
        isStreaming = false
        isPlaying = false
        status = "Reproducción detenida desde el Apple TV"
        detail = "AirCiller ha guardado el punto exacto para continuar después."
    }

    private func enqueue(_ urls: [URL]) {
        var knownPaths = Set(queueItems.map(\.path))
        var updated = queueItems
        for url in urls where MediaFileTypes.accepts(url) && knownPaths.insert(url.path).inserted {
            updated.append(QueueMediaItem(path: url.path, title: url.deletingPathExtension().lastPathComponent))
        }
        queueItems = updated
        HistoryStore.saveQueue(queueItems)
        if !urls.isEmpty, !commandAvailability.canStop {
            status = "Playlist actualizada"
            detail =
                queueItems.count == 1
                ? L10n.text("Hay 1 película en orden estable.")
                : L10n.format("Hay %lld películas en orden estable.", Int64(queueItems.count))
        }
    }

    private func touchRecent(url: URL, duration: Double, position: Double) {
        if let index = recentItems.firstIndex(where: { $0.path == url.path }) {
            recentItems[index].title = url.deletingPathExtension().lastPathComponent
            recentItems[index].lastOpened = Date()
            recentItems[index].lastPosition = position
            if duration > 0 { recentItems[index].duration = duration }
        } else {
            recentItems.insert(
                RecentMediaItem(
                    path: url.path,
                    title: url.deletingPathExtension().lastPathComponent,
                    lastOpened: Date(),
                    lastPosition: position,
                    duration: duration
                ),
                at: 0
            )
        }
        recentItems = Array(recentItems.prefix(HistoryStore.maximumRecentItems))
        if let focusedRecentItemID, !recentItems.contains(where: { $0.id == focusedRecentItemID }) {
            self.focusedRecentItemID = nil
        }
        HistoryStore.saveRecent(recentItems)
    }

    private func saveCurrentPosition(force: Bool) {
        guard let selectedURL, duration > 0 else { return }
        if !force, Date().timeIntervalSince(lastHistorySave) < 5 { return }
        lastHistorySave = Date()
        let position = moviePosition
        let originalDuration = movieDuration
        let storedPosition = position >= originalDuration - 30 ? 0 : position
        if let index = queueItems.firstIndex(where: { $0.path == selectedURL.path }) {
            queueItems[index].lastPosition = position
            queueItems[index].duration = originalDuration
            HistoryStore.saveQueue(queueItems)
        }
        if let index = recentItems.firstIndex(where: { $0.path == selectedURL.path }) {
            recentItems[index].lastPosition = storedPosition
            recentItems[index].duration = originalDuration
            recentItems[index].lastOpened = Date()
        } else {
            touchRecent(url: selectedURL, duration: originalDuration, position: storedPosition)
            return
        }
        HistoryStore.saveRecent(recentItems)
    }

    private func presentError(title: String, detail: String) {
        transitionPower.end()
        hasError = true
        status = title
        self.detail = detail
    }

    private func requestAuthorizationRenewalIfNeeded(_ error: Error, retryAt: Double) -> Bool {
        guard let directError = error as? DirectAirPlayError,
            case .authorizationRequired(let message) = directError
        else {
            return false
        }
        requestAuthorizationRenewal(message: message, retryAt: retryAt)
        return true
    }

    private func requestAuthorizationRenewal(message: String, retryAt: Double) {
        guard authorizationRetryPolicy.beginRenewal() else {
            presentError(
                title: "El Apple TV no aceptó la nueva autorización",
                detail: L10n.format(
                    "AirCiller ha detenido el proceso para evitar el ciclo de códigos y VOD. Pulsa Reproducir si quieres realizar un único intento nuevo. %@",
                    message)
            )
            return
        }
        cancelAuthorizationPreflight()
        pendingStartTime = retryAt
        isPreparing = false
        isStreaming = false
        isPlaying = false
        preparationProgress = 0
        hasError = false
        status = "El Apple TV pide renovar la autorización"
        detail = L10n.format(
            "Introduce aquí el código que aparecerá en el televisor. AirCiller volverá a intentarlo después. %@",
            message)
        authorizationRenewalSessionID = remoteControlSessionID
        airPlay.beginPairing(resumePlayback: true)
    }

    private func cancelAuthorizationPreflight() {
        authorizationPreflight.cancel()
    }

    private func resetStreamSessionMetrics() {
        packagedDemandProfile = nil
        streamTelemetry = .empty
        rebufferEvents = 0
        lastRebufferEvent = .distantPast
    }

    private func makeLocalServer(rootDirectory: URL, sessionID: UUID) -> LocalHTTPServer {
        LocalHTTPServer(
            rootDirectory: rootDirectory,
            telemetryClientAddress: airPlay.selectedDevice?.address,
            deliveryFailureHandler: { [weak self] technicalReason in
                Task { @MainActor [weak self] in
                    guard let self, self.activeSessionID == sessionID else { return }
                    self.playbackLogger.error(
                        "El servidor local dejó de leer la película: \(technicalReason, privacy: .public)"
                    )
                    self.cleanupRuntime()
                    self.isPreparing = false
                    self.isStreaming = false
                    self.isPlaying = false
                    self.hasError = true
                    self.status = "La transmisión local se ha detenido"
                    self.detail =
                        "AirCiller no pudo seguir leyendo la película preparada. Ha cerrado la sesión para evitar una espera infinita. Pulsa Reproducir para continuar desde este punto."
                }
            },
            telemetryHandler: { [weak self] telemetry in
                Task { @MainActor [weak self] in
                    guard let self, self.activeSessionID == sessionID else { return }
                    self.streamTelemetry = telemetry
                }
            }
        )
    }

    private func waitForReceiverMediaRequest(sessionID: UUID) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(20))
        while activeSessionID == sessionID {
            if streamTelemetry.hasConfirmedMediaRequest {
                return
            }
            if clock.now >= deadline {
                airPlay.stop(silently: true)
                throw AirCillerError.receiverDidNotRequestMedia
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw CancellationError()
    }

    private func cleanupRuntime() {
        if let activeMovieTimeline {
            currentTime = activeMovieTimeline.sourcePosition(forPresentation: currentTime)
            duration = activeMovieTimeline.sourceDuration
            self.activeMovieTimeline = nil
        }
        if let activeSessionID { startupTrace?.finish(.cancelled, sessionID: activeSessionID) }
        activeSessionID = nil
        airPlay.stop(silently: true)
        playbackPower.end()
        clearItemObservers()
        if let process = ffmpegProcess {
            CancellableProcess(process).terminate()
        }
        ffmpegProcess = nil
        ffmpegLog = nil
        server?.stop()
        server = nil
        if let temporaryDirectory, temporaryDirectory != preparingHLSDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        preparingHLSDirectory = nil
        temporaryDirectory = nil
        preparationProgress = 0
        nowPlaying.clear()
    }

    private func clearItemObservers() {
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        if let itemEndObserver { NotificationCenter.default.removeObserver(itemEndObserver) }
        if let itemErrorObserver { NotificationCenter.default.removeObserver(itemErrorObserver) }
        itemEndObserver = nil
        itemErrorObserver = nil
    }

    nonisolated private static func cleanupLocalResources(
        process: Process?,
        server: LocalHTTPServer?,
        directory: URL?
    ) {
        if let process { CancellableProcess(process).terminate() }
        server?.stop()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    private func waitForVODCompletion(
        _ build: VODBuildProcess,
        exitTask: Task<Int32, Error>,
        expectedDuration: Double,
        sessionID: UUID,
        preparationName: String = "VOD completo"
    ) async throws {
        defer { exitTask.cancel() }
        while build.process.isRunning {
            try Task.checkCancellation()
            guard activeSessionID == sessionID else { throw CancellationError() }
            let fraction = expectedDuration > 0 ? build.progress.seconds / expectedDuration : 0
            preparationProgress = min(0.88, max(0.01, fraction * 0.88))
            status = L10n.format("Preparando %@…", L10n.text(preparationName))
            let percent = Int((preparationProgress / 0.88 * 100).rounded())
            if let speed = build.progress.speed, speed > 0.01 {
                let remaining = max(0, expectedDuration - build.progress.seconds) / speed
                detail = L10n.format(
                    "%lld %% · %@ · quedan aprox. %@ · vídeo intacto.",
                    Int64(percent),
                    String(format: "%.1f×", speed),
                    TimeFormatting.duration(remaining))
            } else {
                detail = L10n.format("%lld %% · sin recodificar el vídeo.", Int64(percent))
            }
            try await Task.sleep(for: .milliseconds(200))
        }

        let status = try await exitTask.value
        guard status == 0 else {
            throw AirCillerError.ffmpegStopped(build.log.snapshot)
        }
        preparationProgress = 0.90
    }

    nonisolated private static func makeDirectFileProcess(
        input: URL,
        output: URL,
        probe: MediaProbe,
        audio: AudioTrack?,
        outputMode: AudioOutputMode,
        audioDelay: Double,
        subtitle: SubtitleTrack?,
        subtitleDelay: Double
    ) throws -> VODBuildProcess {
        guard let ffmpegURL = Executables.find("ffmpeg") else {
            throw AirCillerError.ffmpegMissing
        }
        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = DirectFileCommandBuilder.arguments(
            input: input,
            output: output,
            probe: probe,
            audio: audio,
            outputMode: outputMode,
            audioDelay: audioDelay,
            subtitle: subtitle,
            subtitleDelay: subtitleDelay
        )

        let errorPipe = Pipe()
        let log = ProcessLogBuffer()
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            log.append(text)
        }
        process.standardError = errorPipe
        let progressPipe = Pipe()
        let progress = ProcessProgressBuffer()
        progressPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            progress.append(text)
        }
        process.standardOutput = progressPipe
        return VODBuildProcess(
            process: process,
            log: log,
            progress: progress,
            errorPipe: errorPipe,
            progressPipe: progressPipe
        )
    }

    nonisolated private static func storagePreflightError(
        fileSize: Int64?,
        sizeMultiplier: Double
    ) -> String? {
        guard let fileSize, fileSize > 0,
            let values = try? FileManager.default.attributesOfFileSystem(
                forPath: FileManager.default.temporaryDirectory.path
            ),
            let free = (values[.systemFreeSize] as? NSNumber)?.int64Value
        else {
            return nil
        }
        let required = max(fileSize + 768_000_000, Int64(Double(fileSize) * sizeMultiplier))
        guard free < required else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return L10n.format(
            "Para conservar el vídeo sin recodificar hacen falta aproximadamente %@ libres; ahora hay %@. AirCiller no borrará ni reducirá nada silenciosamente.",
            formatter.string(fromByteCount: required),
            formatter.string(fromByteCount: free))
    }

    nonisolated private static func cleanupStaleBuffers() {
        try? AirCillerStorage.clearPreparedMedia()
        _ = try? AirCillerStorage.pruneSubtitleCache()
    }
}
