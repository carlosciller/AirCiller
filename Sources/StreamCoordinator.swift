import AVFoundation
import AppKit
import Foundation
import OSLog
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class StreamCoordinator {
    private(set) var selectedURL: URL?
    private(set) var probeInfo: MediaProbe?
    var status = "Listo"
    var detail = "Elige una película y AirCiller comprobará todas sus pistas."
    var isPreparing = false
    var isStreaming = false
    var isPlaying = false
    var hasError = false
    var mediaDescription: String?
    var duration: Double = 0
    var currentTime: Double = 0
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
    private(set) var preferredSubtitleKind: SubtitleTrackPreference =
        UserDefaults.standard.string(forKey: "preferredSubtitleKind")
        .flatMap(SubtitleTrackPreference.init(rawValue:)) ?? .standard

    private(set) var recentItems: [RecentMediaItem] = HistoryStore.loadRecent()
    private(set) var queueItems: [QueueMediaItem] = HistoryStore.loadQueue()
    var showConversionAlert = false
    private(set) var conversionReason = ""

    let player = AVPlayer()
    let network = NetworkMonitor()
    let airPlay = AirPlayController()
    private let nowPlaying = SystemNowPlayingController()
    private let playbackPower = PlaybackPowerAssertion()
    private let playbackLogger = Logger(subsystem: "local.carlosciller.AirCiller", category: "Playback")
    @ObservationIgnored private let launchOptions = AirCillerLaunchOptions()

    @ObservationIgnored private var server: LocalHTTPServer?
    @ObservationIgnored private var ffmpegProcess: Process?
    @ObservationIgnored private var ffmpegLog: ProcessLogBuffer?
    @ObservationIgnored private var temporaryDirectory: URL?

    var activePreparedDirectory: URL? { temporaryDirectory }
    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var authorizationTask: Task<Void, Never>?
    @ObservationIgnored private var authorizationRequestID: UUID?
    @ObservationIgnored private var authorizationRetryPolicy = AirPlayAuthorizationRetryPolicy()
    @ObservationIgnored private let mediaAnalysisTasks = MediaAnalysisTasks()
    @ObservationIgnored private var terminationObserver: NSObjectProtocol?
    @ObservationIgnored private var itemEndObserver: NSObjectProtocol?
    @ObservationIgnored private var itemErrorObserver: NSObjectProtocol?
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var pendingStartTime: Double = 0
    @ObservationIgnored private var lastHistorySave = Date.distantPast
    @ObservationIgnored private var activeSessionID: UUID?
    @ObservationIgnored private var lastRebufferEvent = Date.distantPast

    init() {
        Self.cleanupStaleBuffers()
        player.allowsExternalPlayback = true
        player.automaticallyWaitsToMinimizeStalling = true

        airPlay.onPlaybackUpdate = { [weak self] position, reportedDuration, playing in
            guard let self else { return }
            let previousState = self.isPlaying
            if reportedDuration.isFinite, reportedDuration > 0 {
                self.duration = reportedDuration
            }
            if position.isFinite {
                self.currentTime = min(self.duration, max(0, position))
            }
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
            if self.isStreaming, previousState != playing {
                self.status =
                    playing
                    ? L10n.format(
                        "Reproduciendo en %@", self.airPlay.selectedDevice?.name ?? "Apple TV")
                    : L10n.text("En pausa desde el Apple TV")
                self.detail =
                    playing
                    ? L10n.text("El mando del Apple TV ha reanudado la película.")
                    : L10n.text("La pausa del mando se ha sincronizado con AirCiller.")
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
            let retryTime = self.currentTime
            self.cleanupRuntime()
            self.requestAuthorizationRenewal(message: message, retryAt: retryTime)
        }
        airPlay.onPairingSucceeded = { [weak self] shouldResumePlayback in
            guard let self, shouldResumePlayback, self.selectedURL != nil else { return }
            self.continueStart(at: self.pendingStartTime)
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

    var selectedSubtitle: SubtitleTrack? {
        subtitleTracks.first(where: { $0.id == selectedSubtitleID })
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
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.videoContentTypes

        guard panel.runModal() == .OK, let first = panel.urls.first else { return }
        handleURLs([first] + Array(panel.urls.dropFirst()))
    }

    func addToQueue() {
        let panel = NSOpenPanel()
        panel.title = L10n.text("Añadir a la playlist")
        panel.prompt = L10n.text("Añadir")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.videoContentTypes
        guard panel.runModal() == .OK else { return }
        enqueue(panel.urls)
    }

    func handleURLs(_ urls: [URL]) {
        let acceptedExtensions = Set(["mkv", "mp4", "m4v", "mov"])
        let videos = urls.filter { acceptedExtensions.contains($0.pathExtension.lowercased()) }
        guard let first = videos.first else {
            presentError(
                title: "No hay ninguna película compatible",
                detail: "Arrastra o abre un archivo MKV, MP4, M4V o MOV."
            )
            return
        }
        if videos.count > 1 { enqueue(videos) }
        loadVideo(first, autoStart: false)
    }

    func addExternalSubtitle() {
        guard selectedURL != nil else { return }
        let panel = NSOpenPanel()
        panel.title = L10n.text("Añadir subtítulos")
        panel.prompt = L10n.text("Añadir")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = ["srt", "ass", "ssa", "vtt"].compactMap { extensionName in
            UTType(filenameExtension: extensionName)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let track = MediaProbeService.externalTrack(url: url)
        if !subtitleTracks.contains(where: { $0.id == track.id }) {
            subtitleTracks.append(track)
        }
        selectedSubtitleID = track.id
        status = "Subtítulo externo añadido"
        detail = "Pulsa Aplicar pistas para usarlo."
    }

    func openRecent(_ item: RecentMediaItem) {
        guard FileManager.default.fileExists(atPath: item.path) else {
            removeRecent(item)
            hasError = true
            status = "El archivo ya no está ahí"
            detail = "Se ha retirado del historial."
            return
        }
        loadVideo(item.url, autoStart: false)
    }

    func loadVideo(_ url: URL, autoStart: Bool, startingAt requestedStart: Double? = nil) {
        let commandLineSubtitleIndex = autoStart ? launchOptions.subtitleStreamIndex : nil
        mediaAnalysisTasks.cancelAll()
        stop(resetStatus: false)
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
        currentTime = requestedStart ?? recentItems.first(where: { $0.path == url.path })?.lastPosition ?? 0
        hasError = false
        status = "Analizando la película…"
        detail = "Comprobando duración, Dolby Vision, HDR, audio, subtítulos y capítulos."
        touchRecent(url: url, duration: 0, position: currentTime)

        mediaAnalysisTasks.replacePrimary(
            with: Task { [weak self] in
                guard let self else { return }
                do {
                    let info = try await MediaProbeService.probe(url: url)
                    try Task.checkCancellation()
                    self.probeInfo = info
                    self.audioTracks = info.audioTracks
                    self.subtitleTracks = info.subtitleTracks
                    self.chapters = info.chapters
                    if !self.preferredAudioLanguage.isEmpty,
                        let preferredAudio = AudioTrackSelection.preferredTrack(
                            in: info.audioTracks,
                            language: self.preferredAudioLanguage
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
                    } else if !self.preferredSubtitleLanguage.isEmpty {
                        self.selectedSubtitleID =
                            SubtitleTrackSelection.preferredTrack(
                                in: info.subtitleTracks,
                                language: self.preferredSubtitleLanguage,
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
                    if autoStart { await self.startAfterNetworkSettles() }
                } catch is CancellationError {
                    return
                } catch {
                    self.hasError = true
                    self.status = "No se pudo analizar la película"
                    self.detail = error.localizedDescription
                }
            })
    }

    func start() {
        start(at: currentTime)
    }

    func start(at requestedTime: Double) {
        cancelAuthorizationPreflight()
        authorizationRetryPolicy.reset()
        continueStart(at: requestedTime)
    }

    private func startAfterNetworkSettles() async {
        let deadline = Date().addingTimeInterval(3)
        while !network.isReady, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
        }
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
            status = "Comprobando autorización de AirPlay…"
            detail = "AirCiller continuará automáticamente cuando macOS confirme el acceso seguro."
            Task { [weak self] in
                guard let self else { return }
                await self.airPlay.refreshAuthorization()
                guard self.selectedURL == selectedURL else { return }
                self.continueStart(at: requestedTime)
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
        if let audio = selectedAudio,
            audioOutputMode == .original,
            !audio.canPassThrough
        {
            pendingStartTime = requestedTime
            conversionReason = L10n.format(
                "La pista elegida usa %@, que Apple TV no admite en este HLS. AirCiller puede convertir solamente el audio a E-AC-3 y mantendrá el vídeo intacto.",
                audio.codec.uppercased())
            showConversionAlert = true
            return
        }
        if airPlay.needsAuthorizationValidation {
            pendingStartTime = requestedTime
            isPreparing = true
            status = "Comprobando autorización con el Apple TV…"
            detail = "La credencial se valida antes de preparar el VOD para evitar esperas y reintentos innecesarios."
            let requestID = UUID()
            authorizationRequestID = requestID
            authorizationTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.airPlay.validateAuthorization()
                    guard self.authorizationRequestID == requestID,
                        self.selectedURL == selectedURL
                    else { return }
                    self.authorizationTask = nil
                    self.authorizationRequestID = nil
                    self.isPreparing = false
                    self.continueStart(at: requestedTime)
                } catch is CancellationError {
                    return
                } catch {
                    guard self.authorizationRequestID == requestID else { return }
                    self.authorizationTask = nil
                    self.authorizationRequestID = nil
                    self.isPreparing = false
                    if self.requestAuthorizationRenewalIfNeeded(error, retryAt: requestedTime) {
                        return
                    }
                    self.presentError(
                        title: "No se pudo comprobar la autorización",
                        detail: error.localizedDescription
                    )
                }
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
        if let storageError = Self.storagePreflightError(
            fileSize: info.fileSize,
            sizeMultiplier: 1.12
        ) {
            presentError(title: "No hay espacio temporal suficiente", detail: storageError)
            return
        }

        if info.isHDR, selectedSubtitle != nil {
            beginDirectHDRSubtitleStreaming(url: selectedURL, info: info, requestedTime: requestedTime)
        } else {
            beginStreaming(url: selectedURL, info: info, requestedTime: requestedTime)
        }
    }

    func confirmAudioConversion() {
        showConversionAlert = false
        audioOutputMode = .compatible
        continueStart(at: pendingStartTime)
    }

    func cancelAudioConversion() {
        showConversionAlert = false
        status = "Conversión cancelada"
        detail = "No se ha cambiado ni reproducido nada. Puedes elegir otra pista de audio."
    }

    func applyTrackSettings() {
        if let subtitle = selectedSubtitle, let reason = subtitle.unsupportedReason {
            presentError(title: "Subtítulo no disponible todavía", detail: reason)
            return
        }
        if isStreaming || isPreparing {
            let target = currentTime
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
        guard !chapters.isEmpty else { return }
        let target = chapters.last(where: { $0.start < currentTime - 3 })?.start ?? 0
        seek(to: target)
    }

    func nextChapter() {
        guard let target = chapters.first(where: { $0.start > currentTime + 1 })?.start else { return }
        seek(to: target)
    }

    func stop(resetStatus: Bool = true) {
        saveCurrentPosition(force: true)
        mediaAnalysisTasks.cancelAll()
        streamTask?.cancel()
        streamTask = nil
        cancelAuthorizationPreflight()
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

    func selectQueueItem(_ item: QueueMediaItem) {
        guard queueFileExists(item) else { return }
        loadVideo(item.url, autoStart: false)
    }

    func playQueueItem(_ item: QueueMediaItem) {
        guard queueFileExists(item) else { return }
        loadVideo(item.url, autoStart: true)
    }

    func playQueueItemFromBeginning(_ item: QueueMediaItem) {
        guard queueFileExists(item) else { return }
        loadVideo(item.url, autoStart: true, startingAt: 0)
    }

    func playRecentFromBeginning(_ item: RecentMediaItem) {
        guard FileManager.default.fileExists(atPath: item.path) else {
            removeRecent(item)
            presentError(title: "El archivo ya no está ahí", detail: "Se ha retirado del historial.")
            return
        }
        loadVideo(item.url, autoStart: true, startingAt: 0)
    }

    func removeQueueItem(_ item: QueueMediaItem) {
        queueItems.removeAll(where: { $0.id == item.id })
        HistoryStore.saveQueue(queueItems)
    }

    func moveQueueItems(fromOffsets: IndexSet, toOffset: Int) {
        queueItems = QueueOrdering.moving(queueItems, fromOffsets: fromOffsets, toOffset: toOffset)
        HistoryStore.saveQueue(queueItems)
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

    func moveQueueItemToBeginning(_ item: QueueMediaItem) {
        moveQueueItems(ids: [item.id], before: queueItems.first?.id)
    }

    func moveQueueItemToEnd(_ item: QueueMediaItem) {
        moveQueueItems(ids: [item.id], before: nil)
    }

    func clearQueue() {
        queueItems.removeAll()
        HistoryStore.saveQueue(queueItems)
    }

    func removeRecent(_ item: RecentMediaItem) {
        recentItems.removeAll(where: { $0.id == item.id })
        HistoryStore.saveRecent(recentItems)
    }

    func clearRecent() {
        recentItems.removeAll()
        HistoryStore.saveRecent(recentItems)
    }

    private func queueFileExists(_ item: QueueMediaItem) -> Bool {
        guard FileManager.default.fileExists(atPath: item.path) else {
            removeQueueItem(item)
            presentError(title: "El archivo ya no está ahí", detail: "Se ha retirado de la playlist.")
            return false
        }
        return true
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
                guard try await item.asset.load(.isPlayable) else {
                    throw AirCillerError.invalidVODPackage("AVPlayer no reconoce el MP4 HDR como reproducible.")
                }
                let playerDuration = try await item.asset.load(.duration).seconds
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
                    item.select(option, in: group)
                }
                self.observe(item: item)
                self.player.replaceCurrentItem(with: item)
                let playableStartTime = min(startTime, max(0, prepared.duration - 0.5))
                self.currentTime = playableStartTime
                if playableStartTime > 0.05 { await self.seekPlayer(to: playableStartTime) }
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
                self.status = "Confirmando el stream en el Apple TV…"
                self.detail = "Esperando la primera petición real de vídeo del receptor."
                try await self.waitForReceiverMediaRequest(sessionID: sessionID)
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

    private func beginStreaming(url: URL, info: MediaProbe, requestedTime: Double) {
        let session = prepareStreamSession(
            requestedTime: requestedTime,
            duration: info.duration,
            status: "Preparando la película completa…",
            detail: "Creando un VOD local con duración final. El vídeo original permanece intacto."
        )
        let sessionID = session.id
        let startTime = session.startTime

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
            var sessionProcess: Process?
            do {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("AirCiller-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                sessionDirectory = directory
                guard self.activeSessionID == sessionID else { throw CancellationError() }
                self.temporaryDirectory = directory

                let build = try Self.makeFFmpegProcess(
                    input: url,
                    outputDirectory: directory,
                    probe: info,
                    audio: audio,
                    outputMode: outputMode,
                    audioDelay: chosenAudioDelay,
                    multiplexed: usesDirectHDRRendition
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
                    sessionID: sessionID
                )
                build.closePipes()
                if self.activeSessionID == sessionID {
                    self.ffmpegProcess = nil
                    self.ffmpegLog = nil
                }

                if usesDirectHDRRendition {
                    self.status = "Ajustando la cabecera HDR…"
                    self.detail = "Conservando Dolby Vision/HDR y preparando el formato fMP4 que exige Apple TV."
                    self.preparationProgress = 0.91
                    let initializationURL = directory.appendingPathComponent("video-init.mp4")
                    let firstSegmentURL = directory.appendingPathComponent("video-00000000.m4s")
                    try HDRConfigurationInjector.normalizeHLSFileType(
                        initializationSegment: initializationURL
                    )
                    let isHDR10CompatibleDolbyVision =
                        info.dolbyVisionProfile == 8 && info.dolbyVisionCompatibilityID == 1
                    if info.colorTransfer?.lowercased() == "smpte2084"
                        && (!info.isDolbyVision || isHDR10CompatibleDolbyVision)
                    {
                        try HDRConfigurationInjector.injectStaticMetadata(
                            initializationSegment: initializationURL,
                            firstMediaSegment: firstSegmentURL
                        )
                    }
                }

                try SubtitleService.alignRenditionPlaylists(
                    outputDirectory: directory,
                    expectedDuration: info.duration
                )

                if let subtitle {
                    self.status =
                        subtitle.usesBitmapOCR
                        ? "Leyendo subtítulos gráficos…"
                        : "Alineando subtítulos…"
                    self.detail =
                        subtitle.usesBitmapOCR
                        ? "Apple Vision reconoce la pista gráfica localmente y la convierte en WebVTT seleccionable."
                        : "Creando una pista WebVTT para cada tramo de la película."
                    self.preparationProgress = 0.91
                    try await SubtitleService.prepare(
                        track: subtitle,
                        videoURL: url,
                        delay: chosenSubtitleDelay,
                        videoPlaylistURL: directory.appendingPathComponent("video.m3u8"),
                        outputDirectory: directory,
                        ocrProgress: { [weak self] completed, total in
                            Task { @MainActor [weak self] in
                                self?.reportOCRProgress(
                                    completed: completed,
                                    total: total,
                                    sessionID: sessionID,
                                    baseProgress: 0.91,
                                    span: 0.04
                                )
                            }
                        }
                    )
                    try SubtitleService.alignRenditionPlaylists(
                        outputDirectory: directory,
                        expectedDuration: info.duration
                    )
                }
                if !usesDirectHDRRendition {
                    try SubtitleService.writeMasterPlaylist(
                        probe: info,
                        audio: audio,
                        audioOutputMode: outputMode,
                        subtitle: subtitle,
                        outputDirectory: directory
                    )
                }
                try Task.checkCancellation()
                guard self.activeSessionID == sessionID else { throw CancellationError() }

                self.status = "Comprobando la película preparada…"
                self.detail = "Verificando duración, cierre VOD y sincronía de todas las listas."
                self.preparationProgress = 0.96
                let packagedDuration = try SubtitleService.validatePackage(
                    outputDirectory: directory,
                    expectedDuration: info.duration,
                    hasAudio: audio != nil && !usesDirectHDRRendition,
                    hasSubtitles: subtitle != nil,
                    requiresMasterPlaylist: !usesDirectHDRRendition
                )
                self.packagedDemandProfile = try StreamDemandAnalyzer.packagedHLSProfile(
                    outputDirectory: directory,
                    hasSeparateAudio: audio != nil && !usesDirectHDRRendition
                )

                let localServer = self.makeLocalServer(
                    rootDirectory: directory,
                    sessionID: sessionID
                )
                sessionServer = localServer
                self.server = localServer
                let baseURL = try await localServer.start()
                try Task.checkCancellation()
                guard self.activeSessionID == sessionID else { throw CancellationError() }

                let playbackFile = usesDirectHDRRendition ? "video.m3u8" : "master.m3u8"
                let playbackURL = baseURL.appendingPathComponent(playbackFile)
                let item = AVPlayerItem(url: playbackURL)
                item.preferredForwardBufferDuration = 12
                let isPlayable = try await item.asset.load(.isPlayable)
                guard isPlayable else {
                    throw AirCillerError.invalidVODPackage("AVPlayer no reconoce el paquete como reproducible.")
                }
                let playerDuration = try await item.asset.load(.duration).seconds
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
                    item.select(option, in: group)
                }
                self.observe(item: item)
                self.player.replaceCurrentItem(with: item)
                let playableStartTime = min(startTime, max(0, packagedDuration - 0.5))
                self.currentTime = playableStartTime
                if playableStartTime > 0.05 {
                    await self.seekPlayer(to: playableStartTime)
                }
                self.player.pause()

                self.status = L10n.format(
                    "Conectando con %@…", self.airPlay.selectedDevice?.name ?? "Apple TV")
                self.detail = "Enviando la orden directamente por AirPlay y esperando confirmación real de duración."
                try await self.airPlay.startPlayback(
                    url: playbackURL,
                    position: playableStartTime,
                    duration: packagedDuration,
                    title: self.selectedURL?.deletingPathExtension().lastPathComponent
                )
                self.status = "Confirmando el stream en el Apple TV…"
                self.detail = "Esperando la primera petición real de vídeo del receptor."
                try await self.waitForReceiverMediaRequest(sessionID: sessionID)
                self.authorizationRetryPolicy.reset()

                self.duration = packagedDuration
                self.isPreparing = false
                self.isStreaming = true
                self.isPlaying = true
                self.preparationProgress = 1
                self.status = L10n.format(
                    "Reproduciendo en %@", self.airPlay.selectedDevice?.name ?? "Apple TV")
                self.detail =
                    usesDirectHDRRendition
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
                Self.cleanupLocalResources(
                    process: sessionProcess,
                    server: sessionServer,
                    directory: sessionDirectory
                )
                return
            } catch {
                if self.activeSessionID == sessionID {
                    self.cleanupRuntime()
                } else {
                    Self.cleanupLocalResources(
                        process: sessionProcess,
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
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in
                self?.presentPlaybackFailure(item.error)
            }
        }
        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.playbackFinished() }
        }
        itemErrorObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemNewErrorLogEntry,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.recordErrorLog(for: item)
                if let error = item.error {
                    self?.presentPlaybackFailure(error)
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
        currentTime = duration
        saveCurrentPosition(force: true)
        cleanupRuntime()
        isStreaming = false
        isPlaying = false
        if let selectedURL,
            let currentIndex = queueItems.firstIndex(where: { $0.path == selectedURL.path }),
            queueItems.indices.contains(currentIndex + 1)
        {
            let next = queueItems[currentIndex + 1]
            loadVideo(next.url, autoStart: true)
        } else {
            status = "Reproducción terminada"
            detail = "No hay otro título después en la playlist."
        }
    }

    private func playbackStoppedByReceiver() {
        saveCurrentPosition(force: true)
        cleanupRuntime()
        isPreparing = false
        isStreaming = false
        isPlaying = false
        status = "Reproducción detenida desde el Apple TV"
        detail = "AirCiller ha guardado el punto exacto para continuar después."
    }

    private func enqueue(_ urls: [URL]) {
        for url in urls where !queueItems.contains(where: { $0.path == url.path }) {
            queueItems.append(QueueMediaItem(path: url.path, title: url.deletingPathExtension().lastPathComponent))
        }
        HistoryStore.saveQueue(queueItems)
        if !urls.isEmpty {
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
        HistoryStore.saveRecent(recentItems)
    }

    private func saveCurrentPosition(force: Bool) {
        guard let selectedURL, duration > 0 else { return }
        if !force, Date().timeIntervalSince(lastHistorySave) < 5 { return }
        lastHistorySave = Date()
        let storedPosition = currentTime >= duration - 30 ? 0 : currentTime
        if let index = recentItems.firstIndex(where: { $0.path == selectedURL.path }) {
            recentItems[index].lastPosition = storedPosition
            recentItems[index].duration = duration
            recentItems[index].lastOpened = Date()
        } else {
            touchRecent(url: selectedURL, duration: duration, position: storedPosition)
            return
        }
        HistoryStore.saveRecent(recentItems)
    }

    private func presentError(title: String, detail: String) {
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
        airPlay.beginPairing(resumePlayback: true)
    }

    private func cancelAuthorizationPreflight() {
        authorizationTask?.cancel()
        authorizationTask = nil
        authorizationRequestID = nil
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
            telemetryClientAddress: airPlay.selectedDevice?.address
        ) { [weak self] telemetry in
            Task { @MainActor [weak self] in
                guard let self, self.activeSessionID == sessionID else { return }
                self.streamTelemetry = telemetry
            }
        }
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
        activeSessionID = nil
        playbackPower.end()
        clearItemObservers()
        if let process = ffmpegProcess {
            CancellableProcess(process).terminate()
        }
        ffmpegProcess = nil
        ffmpegLog = nil
        server?.stop()
        server = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
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

    nonisolated private static func makeFFmpegProcess(
        input: URL,
        outputDirectory: URL,
        probe: MediaProbe,
        audio: AudioTrack?,
        outputMode: AudioOutputMode,
        audioDelay: Double,
        multiplexed: Bool = false
    ) throws -> VODBuildProcess {
        guard let ffmpegURL = Executables.find("ffmpeg") else {
            throw AirCillerError.ffmpegMissing
        }

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments =
            multiplexed
            ? VODCommandBuilder.multiplexedArguments(
                input: input,
                outputDirectory: outputDirectory,
                probe: probe,
                audio: audio,
                outputMode: outputMode,
                audioDelay: audioDelay
            )
            : VODCommandBuilder.arguments(
                input: input,
                outputDirectory: outputDirectory,
                probe: probe,
                audio: audio,
                outputMode: outputMode,
                audioDelay: audioDelay
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

    nonisolated private static var videoContentTypes: [UTType] {
        var types: [UTType] = [.movie, .mpeg4Movie, .quickTimeMovie]
        for extensionName in ["mkv", "m4v", "mov", "mp4"] {
            if let type = UTType(filenameExtension: extensionName) { types.append(type) }
        }
        return Array(Set(types))
    }

    nonisolated private static func cleanupStaleBuffers() {
        AirCillerStorage.clearPreparedMedia()
        _ = try? AirCillerStorage.pruneSubtitleCache()
    }
}
