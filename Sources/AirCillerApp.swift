import AVFoundation
import AVKit
import AppKit
import SwiftUI

// The macOS 27 command-line SDK exposes a State macro, but the lightweight
// Command Line Tools package does not ship SwiftUIMacros. Refer to the stable
// property-wrapper type explicitly so standalone builds do not depend on it.
private typealias AirCillerState<Value> = SwiftUI.State<Value>

@main
struct AirCillerApp: App {
    @NSApplicationDelegateAdaptor(AirCillerAppDelegate.self) private var appDelegate
    @AirCillerState private var coordinator = StreamCoordinator()

    var body: some Scene {
        Window("AirCiller", id: "main") {
            ContentView(coordinator: coordinator, appDelegate: appDelegate)
                .frame(minWidth: 1_080, minHeight: 760)
        }
        .defaultSize(width: 1_080, height: 812)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Buscar actualizaciones…") {
                    appDelegate.updateController.checkForUpdates()
                }
                .disabled(!appDelegate.updateController.canCheckForUpdates)
            }
            CommandGroup(replacing: .newItem) {
                Button("Abrir película…") { coordinator.chooseVideos() }
                    .keyboardShortcut("o", modifiers: .command)
                Button("Añadir a la playlist…") { coordinator.addToQueue() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("Reproducción") {
                Button(L10n.text(coordinator.isPlaying ? "Pausa" : "Reproducir")) {
                    coordinator.togglePlayback()
                }
                .keyboardShortcut(.space, modifiers: [])
                Button("Retroceder 10 segundos") { coordinator.skip(by: -10) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("Avanzar 10 segundos") { coordinator.skip(by: 10) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("Retroceder 30 segundos") { coordinator.skip(by: -30) }
                    .keyboardShortcut(.leftArrow, modifiers: .option)
                Button("Avanzar 30 segundos") { coordinator.skip(by: 30) }
                    .keyboardShortcut(.rightArrow, modifiers: .option)
                Divider()
                Button("Detener") { coordinator.stop() }
                    .keyboardShortcut(".", modifiers: .command)
            }
            CommandMenu("Playlist") {
                Button("Mover arriba") {
                    coordinator.moveFocusedQueueItem(by: -1)
                }
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                .disabled(!coordinator.canMoveFocusedQueueItemUp)

                Button("Mover abajo") {
                    coordinator.moveFocusedQueueItem(by: 1)
                }
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                .disabled(!coordinator.canMoveFocusedQueueItemDown)
            }
        }

        Settings {
            AirCillerSettingsView(
                coordinator: coordinator,
                updateController: appDelegate.updateController
            )
        }
    }
}

@MainActor
final class AirCillerAppDelegate: NSObject, NSApplicationDelegate {
    let updateController = UpdateController()

    private var pendingURLs: [URL] = []
    private var openHandler: (([URL]) -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        updateController.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        if let openHandler {
            openHandler(urls)
        } else {
            pendingURLs.append(contentsOf: urls)
        }
    }

    func installOpenHandler(_ handler: @escaping ([URL]) -> Void) {
        openHandler = handler
        guard !pendingURLs.isEmpty else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        handler(urls)
    }

    func removeOpenHandler() {
        openHandler = nil
    }
}

struct ContentView: View {
    @Bindable var coordinator: StreamCoordinator
    let appDelegate: AirCillerAppDelegate
    @AirCillerState private var libraryTab: LibraryTab = .playlist
    @AirCillerState private var showingTracks = false
    @AirCillerState private var showingStreamInfo = false
    @AirCillerState private var isScrubbing = false
    @AirCillerState private var scrubTime: Double = 0

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(coordinator: coordinator, selectedTab: $libraryTab)
                .navigationSplitViewColumnWidth(min: 290, ideal: 330, max: 410)
        } detail: {
            ZStack {
                AirCillerBackdrop()
                mainContent
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    NetworkBadge(monitor: coordinator.network)

                    AirPlayDevicePicker(controller: coordinator.airPlay)

                    openMovieButton
                }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .alert("AirCiller necesita convertir el audio", isPresented: $coordinator.showConversionAlert) {
            Button("Cancelar", role: .cancel) { coordinator.cancelAudioConversion() }
            Button("Convertir solo el audio") { coordinator.confirmAudioConversion() }
        } message: {
            Text(L10n.text(coordinator.conversionReason))
        }
        .sheet(
            isPresented: Binding(
                get: { coordinator.airPlay.isPairingPresented },
                set: { coordinator.airPlay.isPairingPresented = $0 }
            )
        ) {
            AirPlayPairingView(controller: coordinator.airPlay)
        }
        .onAppear {
            appDelegate.installOpenHandler { urls in
                coordinator.handleURLs(urls)
            }
            synchronizeUpdateAvailability()
        }
        .onDisappear {
            appDelegate.removeOpenHandler()
            coordinator.stop(resetStatus: false)
        }
        .onChange(of: coordinator.isPreparing) { _, _ in
            synchronizeUpdateAvailability()
        }
        .onChange(of: coordinator.isStreaming) { _, _ in
            synchronizeUpdateAvailability()
        }
        .dropDestination(for: URL.self) { urls, _ in
            coordinator.handleURLs(urls)
            return true
        }
    }

    private func synchronizeUpdateAvailability() {
        appDelegate.updateController.setPlaybackBusy(
            coordinator.isPreparing || coordinator.isStreaming
        )
    }

    @ViewBuilder
    private var mainContent: some View {
        if coordinator.selectedURL == nil {
            ContentUnavailableView {
                Label("Elige una película", systemImage: "airplayvideo")
            } description: {
                Text("Abre una película o arrástrala aquí. AirCiller conserva el vídeo original.")
            } actions: {
                Button("Abrir película…") { coordinator.chooseVideos() }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        playerStage
                            .frame(height: playerHeight(availableHeight: proxy.size.height))
                            .animation(.smooth(duration: 0.36), value: coordinator.isStreaming)
                        badgeStrip
                        informationPanels
                    }
                    .frame(maxWidth: 1_080)
                    .padding(.horizontal, 26)
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(displayTitle)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                    .textSelection(.enabled)
                if !headerDetail.isEmpty {
                    Text(headerDetail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()

            if let device = coordinator.airPlay.selectedDevice {
                VStack(alignment: .trailing, spacing: 4) {
                    Label(
                        L10n.text(coordinator.airPlay.isConnected ? "Conectado" : "Preparado"),
                        systemImage: coordinator.airPlay.isConnected ? "airplayvideo.circle.fill" : "airplayvideo"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    Text(device.name)
                        .font(.headline)
                        .lineLimit(1)
                }
            }
        }
    }

    private var displayTitle: String {
        coordinator.selectedURL?.deletingPathExtension().lastPathComponent.softWrappedFilename
            ?? L10n.text("Tu cine. En la pantalla grande.")
    }

    private var headerDetail: String {
        if coordinator.selectedURL == nil {
            return L10n.text("Abre una película o arrástrala aquí. AirCiller conserva el vídeo original.")
        }
        if coordinator.isStreaming {
            return L10n.text(coordinator.status)
        }
        if coordinator.isPreparing {
            return L10n.text(coordinator.status)
        }
        return ""
    }

    private var openMovieButton: some View {
        Button {
            coordinator.chooseVideos()
        } label: {
            Label("Abrir película", systemImage: "plus")
        }
    }

    private var player: some View {
        PlayerView(player: coordinator.player)
            .background(Color.black)
            .overlay {
                if !coordinator.isStreaming && !coordinator.isPreparing {
                    ZStack {
                        LinearGradient(
                            colors: [Color.black.opacity(0.08), Color.black.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        VStack(spacing: 13) {
                            Image(systemName: coordinator.selectedURL == nil ? "airplayvideo" : "play.fill")
                                .font(.system(size: 45, weight: .semibold))
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(Color.airCillerYellow)
                            Text(
                                L10n.text(
                                    coordinator.selectedURL == nil ? "Elige una película" : "Lista para reproducir")
                            )
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                            if let name = coordinator.selectedURL?.lastPathComponent {
                                Text(name.softWrappedFilename)
                                    .font(.callout)
                                    .foregroundStyle(.white.opacity(0.68))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 50)
                            }
                        }
                        .offset(y: -58)
                    }
                } else if coordinator.isPreparing {
                    ZStack {
                        Color.black.opacity(0.72)
                        VStack(spacing: 12) {
                            ProgressView(value: coordinator.preparationProgress)
                                .frame(width: 240)
                                .controlSize(.large)
                            Text(L10n.text(coordinator.status))
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("\(Int((coordinator.preparationProgress * 100).rounded())) %")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.7))
                        }
                        .offset(y: -58)
                    }
                } else if coordinator.isStreaming {
                    ZStack {
                        Color.black.opacity(0.62)
                        LinearGradient(
                            colors: [Color.clear, Color.black.opacity(0.45)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        VStack(spacing: 9) {
                            Image(systemName: coordinator.isPlaying ? "airplayvideo.circle.fill" : "pause.circle.fill")
                                .font(.system(size: 34, weight: .medium))
                                .symbolRenderingMode(.hierarchical)
                            Text(
                                L10n.text(
                                    coordinator.isPlaying ? "Reproduciendo en el Apple TV" : "En pausa en el Apple TV")
                            )
                            .font(.headline)
                        }
                        .foregroundStyle(.white.opacity(0.86))
                        .offset(y: -48)
                    }
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 28, y: 14)
    }

    private var playerStage: some View {
        ZStack(alignment: .bottom) {
            player
            transportPanel
                .padding(18)
        }
    }

    private func playerHeight(availableHeight: CGFloat) -> CGFloat {
        if coordinator.isStreaming {
            return max(260, min(310, availableHeight * 0.31))
        }
        return max(315, min(450, availableHeight * 0.42))
    }

    @ViewBuilder
    private var badgeStrip: some View {
        if coordinator.mediaBadges.isEmpty {
            HStack {
                Text(L10n.text(coordinator.mediaDescription ?? "La información técnica aparecerá aquí"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(coordinator.mediaBadges.enumerated()), id: \.element.id) { index, badge in
                        if index > 0 {
                            Divider()
                                .frame(height: 42)
                                .padding(.horizontal, 17)
                        }
                        MediaBadgeView(badge: badge)
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var transportPanel: some View {
        VStack(spacing: 12) {
            timeline
            playbackControls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .modifier(PlaybackControlSurface())
    }

    private var timeline: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubTime : coordinator.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...max(coordinator.duration, 1),
                onEditingChanged: { editing in
                    if editing {
                        isScrubbing = true
                        scrubTime = coordinator.currentTime
                    } else {
                        isScrubbing = false
                        coordinator.seek(to: scrubTime)
                    }
                }
            )
            .accessibilityLabel("Posición de reproducción")
            .disabled(coordinator.duration <= 0 || coordinator.isPreparing)

            HStack {
                Text(TimeFormatting.duration(isScrubbing ? scrubTime : coordinator.currentTime))
                Spacer()
                Text(
                    "−\(TimeFormatting.duration(max(0, coordinator.duration - (isScrubbing ? scrubTime : coordinator.currentTime))))"
                )
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 12) {
            playbackInformationButton
            Spacer(minLength: 0)
            HStack(spacing: 9) {
                Button {
                    coordinator.previousChapter()
                } label: {
                    Image(systemName: "backward.end.fill")
                }
                .airCillerGlassControl()
                .help("Capítulo anterior")
                .accessibilityLabel("Capítulo anterior")
                .disabled(coordinator.chapters.isEmpty || coordinator.isPreparing)

                skipButton(seconds: -10, symbol: "gobackward.10")

                Button {
                    coordinator.togglePlayback()
                } label: {
                    Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 19, weight: .bold))
                        .frame(width: 46, height: 32)
                }
                .airCillerGlassControl()
                .accessibilityLabel(coordinator.isPlaying ? Text("Pausa") : Text("Reproducir"))
                .disabled(coordinator.selectedURL == nil || coordinator.probeInfo == nil || coordinator.isPreparing)

                skipButton(seconds: 10, symbol: "goforward.10")

                Button {
                    coordinator.nextChapter()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .airCillerGlassControl()
                .help("Capítulo siguiente")
                .accessibilityLabel("Capítulo siguiente")
                .disabled(coordinator.chapters.isEmpty || coordinator.isPreparing)
            }

            Spacer(minLength: 0)
            HStack(spacing: 9) {
                Button {
                    showingStreamInfo = false
                    showingTracks.toggle()
                } label: {
                    Label("Audio y subtítulos", systemImage: "captions.bubble")
                        .labelStyle(.iconOnly)
                }
                .airCillerGlassControl()
                .help("Audio y subtítulos")
                .popover(isPresented: $showingTracks, arrowEdge: .bottom) {
                    TrackSettingsView(coordinator: coordinator, isPresented: $showingTracks)
                }
                .disabled(coordinator.probeInfo == nil || coordinator.isPreparing)

                Button {
                    coordinator.stop()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .airCillerGlassControl()
                .help("Detener")
                .disabled(!coordinator.isStreaming && !coordinator.isPreparing)
            }
        }
        .controlSize(.regular)
    }

    private var playbackInformationButton: some View {
        Button {
            showingTracks = false
            showingStreamInfo.toggle()
        } label: {
            Label("Información de reproducción", systemImage: "info.circle")
                .labelStyle(.iconOnly)
        }
        .airCillerGlassControl()
        .foregroundStyle(streamInfoButtonColor)
        .help("Información de reproducción")
        .popover(isPresented: $showingStreamInfo, arrowEdge: .bottom) {
            PlaybackInformationView(coordinator: coordinator)
        }
        .disabled(coordinator.probeInfo == nil || coordinator.isPreparing)
    }

    private func skipButton(seconds: Double, symbol: String) -> some View {
        Button {
            coordinator.skip(by: seconds)
        } label: {
            Image(systemName: symbol)
        }
        .airCillerGlassControl()
        .help(
            seconds < 0
                ? L10n.format("Retroceder %lld segundos", Int64(abs(seconds)))
                : L10n.format("Avanzar %lld segundos", Int64(seconds))
        )
        .accessibilityLabel(
            seconds < 0
                ? L10n.format("Retroceder %lld segundos", Int64(abs(seconds)))
                : L10n.format("Avanzar %lld segundos", Int64(seconds))
        )
        .disabled(coordinator.duration <= 0 || coordinator.isPreparing)
    }

    private var outputPlan: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Salida", systemImage: "waveform.path.ecg.rectangle")
                .font(.headline)
            PlanRow(symbol: "film.fill", text: L10n.text(coordinator.videoPlan), warning: false)
            PlanRow(
                symbol: "speaker.wave.2.fill",
                text: L10n.text(coordinator.audioPlan),
                warning: coordinator.audioOutputMode != .original || coordinator.selectedAudio?.canPassThrough == false
            )
            PlanRow(
                symbol: "captions.bubble.fill",
                text: L10n.text(coordinator.subtitlePlan),
                warning: coordinator.selectedSubtitle?.isSelectable == false
            )
        }
        .font(.caption)
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .airCillerContentCard(cornerRadius: 18)
    }

    private var statusRow: some View {
        HStack(spacing: 10) {
            if coordinator.isPreparing {
                ProgressView(value: coordinator.preparationProgress)
                    .frame(width: 74)
            } else {
                Image(systemName: coordinator.hasError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(coordinator.hasError ? .orange : .green)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.text(coordinator.status)).font(.callout.weight(.semibold))
                Text(L10n.text(coordinator.detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .airCillerContentCard(cornerRadius: 18)
    }

    private var informationPanels: some View {
        Group {
            if coordinator.selectedURL != nil,
                !coordinator.isStreaming || coordinator.isPreparing || coordinator.hasError
            {
                HStack(alignment: .top, spacing: 14) {
                    statusRow
                    outputPlan
                }
            } else if streamNeedsAttention {
                streamWarningRow
            }
        }
    }

    private var streamNeedsAttention: Bool {
        switch coordinator.streamHealthLevel {
        case .tight, .insufficient, .error:
            return true
        case .pending, .excellent, .good:
            return false
        }
    }

    private var streamInfoButtonColor: Color {
        switch coordinator.streamHealthLevel {
        case .tight: return .orange
        case .insufficient, .error: return .red
        case .pending, .excellent, .good: return .primary
        }
    }

    private var streamWarningRow: some View {
        HStack(spacing: 11) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(coordinator.streamHealthLevel == .tight ? .orange : .red)
            VStack(alignment: .leading, spacing: 3) {
                Text(streamWarningTitle)
                    .font(.callout.weight(.semibold))
                Text("Abre Información de reproducción para ver la causa y el margen disponible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .airCillerContentCard(cornerRadius: 18)
    }

    private var streamWarningTitle: String {
        if coordinator.rebufferEvents > 0 {
            return coordinator.rebufferEvents == 1
                ? L10n.text("Apple TV ha tenido que esperar una vez")
                : L10n.format("Apple TV ha tenido que esperar %lld veces", Int64(coordinator.rebufferEvents))
        }
        switch coordinator.streamHealthLevel {
        case .tight: return L10n.text("La conexión tiene poco margen para los picos de esta película")
        case .insufficient: return L10n.text("La película puede pedir más caudal del disponible")
        case .error: return L10n.text("Se ha interrumpido una transferencia inesperadamente")
        case .pending, .excellent, .good: return L10n.text("Revisa la reproducción")
        }
    }
}

struct PlaybackInformationView: View {
    var coordinator: StreamCoordinator
    @AirCillerState private var showingTechnicalDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: healthSymbol)
                    .font(.title2)
                    .foregroundStyle(healthColor)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 4) {
                    Text(healthTitle)
                        .font(.headline)
                    Text(healthSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Divider()

            VStack(spacing: 11) {
                PlaybackInformationRow(title: "Necesita", value: demandText)
                PlaybackInformationRow(title: "Disponible", value: capacityText)
                PlaybackInformationRow(title: "Margen", value: marginText)
            }

            DisclosureGroup("Detalles técnicos", isExpanded: $showingTechnicalDetails) {
                VStack(spacing: 9) {
                    Divider()
                    PlaybackInformationRow(title: "Media del archivo", value: bitrate(demand?.averageBitsPerSecond))
                    PlaybackInformationRow(title: "Objetivo seguro", value: bitrate(demand?.safeTargetBitsPerSecond))
                    PlaybackInformationRow(
                        title: "Caudal activo", value: bitrate(coordinator.streamTelemetry.activeBitsPerSecond))
                    PlaybackInformationRow(
                        title: "Datos enviados", value: byteCount(coordinator.streamTelemetry.totalBytesSent))
                    PlaybackInformationRow(
                        title: "Transferencias",
                        value: L10n.format(
                            "%lld completadas", Int64(coordinator.streamTelemetry.completedTransfers)))
                    PlaybackInformationRow(title: "Esperas", value: "\(coordinator.rebufferEvents)")
                    PlaybackInformationRow(title: "Vídeo", value: coordinator.videoPlan)
                    PlaybackInformationRow(title: "Audio", value: coordinator.audioPlan)
                    PlaybackInformationRow(title: "Subtítulos", value: coordinator.subtitlePlan)
                }
                .padding(.top, 7)
            }
            .font(.callout.weight(.medium))

            Text("Mide la red local entre este Mac y el Apple TV; no mide Internet.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .frame(width: 430)
    }

    private var demand: StreamDemandProfile? { coordinator.streamDemandProfile }

    private var healthSymbol: String {
        switch coordinator.streamHealthLevel {
        case .pending: return "gauge.with.dots.needle.0percent"
        case .excellent: return "gauge.with.dots.needle.100percent"
        case .good: return "gauge.with.dots.needle.67percent"
        case .tight: return "gauge.with.dots.needle.33percent"
        case .insufficient, .error: return "exclamationmark.triangle.fill"
        }
    }

    private var healthColor: Color {
        switch coordinator.streamHealthLevel {
        case .excellent, .good: return .green
        case .tight: return .orange
        case .insufficient, .error: return .red
        case .pending: return .secondary
        }
    }

    private var healthTitle: String {
        switch coordinator.streamHealthLevel {
        case .pending: return L10n.text("Esperando la medición")
        case .excellent: return L10n.text("Conexión excelente")
        case .good: return L10n.text("Conexión preparada")
        case .tight: return L10n.text("Margen justo")
        case .insufficient: return L10n.text("Caudal insuficiente")
        case .error: return L10n.text("Error de entrega")
        }
    }

    private var healthSummary: String {
        if coordinator.rebufferEvents > 0 {
            return coordinator.rebufferEvents == 1
                ? L10n.text("El Apple TV ha esperado una vez durante esta reproducción.")
                : L10n.format(
                    "El Apple TV ha esperado %lld veces durante esta reproducción.",
                    Int64(coordinator.rebufferEvents))
        }
        guard let ratio = capacityRatio else {
            return L10n.text("AirCiller calculará el margen cuando el Apple TV empiece a descargar la película.")
        }
        switch coordinator.streamHealthLevel {
        case .excellent:
            return L10n.format(
                "La red ofrece %@ el caudal del pico más exigente de la película.", ratioText(ratio))
        case .good:
            return L10n.text("Hay margen suficiente para los picos medidos en el archivo.")
        case .tight:
            return L10n.text("Debería reproducir, pero una variación de la red podría provocar una espera.")
        case .insufficient:
            return L10n.text("El pico más exigente supera el caudal observado hacia el Apple TV.")
        case .error:
            return L10n.text("Apple TV cerró una transferencia de una forma que AirCiller no esperaba.")
        case .pending:
            return L10n.text("AirCiller está reuniendo datos de la reproducción.")
        }
    }

    private var demandText: String {
        guard let peak = demand?.peakBitsPerSecond else { return L10n.text("Analizando…") }
        return L10n.format("%@ en el pico", bitrate(peak))
    }

    private var capacityText: String {
        guard let capacity = coordinator.streamTelemetry.observedCapacityBitsPerSecond else {
            return L10n.text("Se medirá al reproducir")
        }
        return bitrate(capacity)
    }

    private var marginText: String {
        guard let ratio = capacityRatio else { return L10n.text("Pendiente") }
        return ratioText(ratio)
    }

    private var capacityRatio: Double? {
        guard let capacity = coordinator.streamTelemetry.observedCapacityBitsPerSecond,
            let peak = demand?.peakBitsPerSecond,
            peak > 0
        else { return nil }
        return capacity / peak
    }

    private func ratioText(_ ratio: Double) -> String {
        String(format: "%.1f×", ratio)
    }

    private func bitrate(_ bitsPerSecond: Double?) -> String {
        guard let bitsPerSecond, bitsPerSecond.isFinite, bitsPerSecond >= 0 else { return "—" }
        if bitsPerSecond >= 1_000_000_000 {
            return String(format: "%.2f Gb/s", bitsPerSecond / 1_000_000_000)
        }
        if bitsPerSecond >= 10_000_000 {
            return String(format: "%.0f Mb/s", bitsPerSecond / 1_000_000)
        }
        if bitsPerSecond >= 1_000_000 {
            return String(format: "%.1f Mb/s", bitsPerSecond / 1_000_000)
        }
        return String(format: "%.0f kb/s", bitsPerSecond / 1_000)
    }

    private func byteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct PlaybackInformationRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(L10n.text(title))
                .foregroundStyle(.secondary)
            Spacer(minLength: 18)
            Text(L10n.text(value))
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.callout)
    }
}

enum LibraryTab: String, CaseIterable, Identifiable {
    case playlist = "Playlist"
    case recent = "Recientes"
    var id: String { rawValue }
}

struct LibrarySidebar: View {
    var coordinator: StreamCoordinator
    @Binding var selectedTab: LibraryTab
    @AirCillerState private var selectedRecentID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 1) {
                    Text("AirCiller")
                        .font(.headline)
                    Text("Tu biblioteca")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 15)
            .padding(.top, 14)
            .padding(.bottom, 16)

            Picker("Tu biblioteca", selection: $selectedTab) {
                ForEach(LibraryTab.allCases) { tab in
                    Text(L10n.text(tab.rawValue)).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 9)
            .padding(.bottom, 12)

            Divider()

            HStack {
                Text(L10n.text(selectedTab.rawValue))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(selectedTab == .playlist ? coordinator.queueItems.count : coordinator.recentItems.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 13)
            .padding(.bottom, 7)

            if selectedTab == .recent {
                recentList
            } else {
                playlistView
            }
        }
        .onChange(of: selectedTab) { _, tab in
            if tab == .recent { coordinator.clearQueueFocus() }
        }
    }

    private var recentList: some View {
        VStack(spacing: 8) {
            if coordinator.recentItems.isEmpty {
                LibraryEmptyView(symbol: "clock.arrow.circlepath", text: "Aquí aparecerán las películas que abras")
            } else {
                List(selection: $selectedRecentID) {
                    ForEach(coordinator.recentItems) { item in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.title.softWrappedFilename)
                                .font(.callout.weight(.medium))
                                .lineLimit(2)
                                .truncationMode(.tail)
                                .frame(minHeight: 34, alignment: .topLeading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            if item.duration > 0 {
                                ProgressView(value: item.progress)
                                Text(
                                    item.lastPosition > 0
                                        ? L10n.format(
                                            "Continuar en %@",
                                            TimeFormatting.duration(item.lastPosition))
                                        : TimeFormatting.duration(item.duration)
                                )
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                        .tag(item.id)
                        .help(item.title)
                    }
                }
                .listStyle(.sidebar)
                .contextMenu(forSelectionType: String.self) { ids in
                    if let item = coordinator.recentItems.first(where: { ids.contains($0.id) }) {
                        Button("Reproducir") { coordinator.playRecent(item) }
                        Button("Reproducir desde el inicio") {
                            coordinator.playRecentFromBeginning(item)
                        }
                        Divider()
                        Button("Quitar de Recientes", role: .destructive) { coordinator.removeRecent(item) }
                    }
                } primaryAction: { ids in
                    if let item = coordinator.recentItems.first(where: { ids.contains($0.id) }) {
                        coordinator.playRecent(item)
                    }
                }
                Button("Borrar historial", role: .destructive) { coordinator.clearRecent() }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var playlistView: some View {
        VStack(spacing: 8) {
            if coordinator.queueItems.isEmpty {
                LibraryEmptyView(
                    symbol: "list.bullet.rectangle.portrait",
                    text: "Añade películas y ordénalas para reproducirlas seguidas")
            } else {
                NativePlaylistTable(streamCoordinator: coordinator)
            }
            HStack {
                Button {
                    coordinator.addToQueue()
                } label: {
                    Label("Añadir", systemImage: "plus")
                }
                if !coordinator.queueItems.isEmpty {
                    Button("Vaciar", role: .destructive) { coordinator.clearQueue() }
                }
            }
            .buttonStyle(.bordered)
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
        .frame(maxHeight: .infinity)
    }
}

struct PlaylistMediaRow: View {
    let index: Int
    let item: QueueMediaItem
    let isCurrentMedia: Bool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            HStack(alignment: .center, spacing: 9) {
                Group {
                    if isCurrentMedia {
                        Image(systemName: "play.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(
                                isSelected
                                    ? Color(nsColor: .alternateSelectedControlTextColor)
                                    : Color.airCillerYellow
                            )
                    } else {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(
                                isSelected
                                    ? Color(nsColor: .alternateSelectedControlTextColor).opacity(0.76)
                                    : Color.secondary
                            )
                    }
                }
                .frame(width: 20, alignment: .trailing)

                Text(item.title.softWrappedFilename)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(
                        isSelected ? Color(nsColor: .alternateSelectedControlTextColor) : Color.primary
                    )
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(
                    isSelected
                        ? Color(nsColor: .alternateSelectedControlTextColor).opacity(0.76)
                        : Color.secondary
                )
                .frame(width: 30, height: 38)
                .contentShape(Rectangle())
                .accessibilityLabel("Arrastrar para ordenar")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .help(item.title)
    }
}

struct TrackSettingsView: View {
    @Bindable var coordinator: StreamCoordinator
    @Binding var isPresented: Bool
    @AirCillerState private var showingOpenSubtitles = false
    @AirCillerState private var draft: TrackSettings
    private let videoURL: URL?

    init(coordinator: StreamCoordinator, isPresented: Binding<Bool>) {
        self.coordinator = coordinator
        _isPresented = isPresented
        _draft = AirCillerState(initialValue: coordinator.trackSettings)
        videoURL = coordinator.selectedURL
    }

    private var selectedSubtitle: SubtitleTrack? {
        coordinator.subtitleTracks.first { $0.id == draft.subtitleID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pistas y sincronización")
                .font(.title3.bold())

            GroupBox("Audio") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Pista de audio", selection: selectedAudio) {
                        Text("Sin audio").tag(String?.none)
                        ForEach(coordinator.audioTracks) { track in
                            Text("\(L10n.text(track.displayName)) · \(L10n.text(track.technicalDescription))")
                                .tag(Optional(track.id))
                        }
                    }
                    Picker("Formato de salida", selection: $draft.audioOutputMode) {
                        ForEach(AudioOutputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(draft.audioID == nil)
                    Label(
                        draft.audioOutputMode.explanation,
                        systemImage: draft.audioOutputMode == .original
                            ? "checkmark.circle"
                            : "arrow.triangle.2.circlepath"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    HStack {
                        Stepper(value: $draft.audioDelay, in: -5...5, step: 0.05) {
                            Text(L10n.format("Sincronía: %@ s", signed(draft.audioDelay)))
                                .monospacedDigit()
                        }
                        Button("Restablecer") { draft.audioDelay = 0 }
                            .font(.caption)
                    }
                    Text("Valores positivos retrasan el audio; negativos lo adelantan.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(6)
            }

            GroupBox("Subtítulos") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Pista", selection: $draft.subtitleID) {
                        Text("Desactivados").tag(String?.none)
                        ForEach(coordinator.subtitleTracks) { track in
                            Text(
                                track.isSelectable
                                    ? L10n.text(track.displayName)
                                    : "⚠︎ \(L10n.text(track.displayName)) — \(track.codec.uppercased())"
                            )
                            .tag(Optional(track.id))
                        }
                    }
                    Button {
                        if let track = coordinator.chooseExternalSubtitle() {
                            draft.subtitleID = track.id
                        }
                    } label: {
                        Label("Añadir SRT, ASS o VTT…", systemImage: "plus")
                    }
                    .buttonStyle(.link)

                    Button {
                        showingOpenSubtitles = true
                    } label: {
                        Label("Buscar en OpenSubtitles…", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.link)
                    .disabled(coordinator.selectedURL == nil)

                    if let reason = selectedSubtitle?.unsupportedReason {
                        Label(L10n.text(reason), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if let notice = selectedSubtitle?.stylingNotice {
                        Label(L10n.text(notice), systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Stepper(value: $draft.subtitleDelay, in: -10...10, step: 0.1) {
                            Text(L10n.format("Sincronía: %@ s", signed(draft.subtitleDelay)))
                                .monospacedDigit()
                        }
                        Button("Restablecer") { draft.subtitleDelay = 0 }
                            .font(.caption)
                    }
                    Text(
                        L10n.text(
                            selectedSubtitle?.usesBitmapOCR == true
                                ? "El primer uso puede tardar mientras se reconoce la pista completa. El resultado queda en una caché local para las siguientes reproducciones."
                                : selectedSubtitle?.usesAdvancedTextStyling == true
                                    ? (coordinator.probeInfo?.isHDR == true
                                        ? "En HDR se conserva como pista seleccionable, pero Apple TV simplifica el diseño ASS."
                                        : "Se conserva la posición ASS. Apple TV mantiene el control final de tamaño y accesibilidad.")
                                    : "El tamaño y la posición los controla Apple TV desde sus preferencias de accesibilidad."
                        )
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    Label(
                        "SDH incluye diálogo, identificación del hablante y descripciones de sonidos o música.",
                        systemImage: "info.circle"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(6)
            }

            HStack {
                Spacer()
                Button("Cancelar") { isPresented = false }
                    .keyboardShortcut(.cancelAction)
                Button("Aplicar cambios") {
                    guard coordinator.selectedURL == videoURL else { return }
                    coordinator.trackSettings = draft
                    isPresented = false
                    coordinator.applyTrackSettings()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 620)
        .sheet(isPresented: $showingOpenSubtitles) {
            if let videoURL {
                OpenSubtitlesSearchView(
                    videoURL: videoURL,
                    preferredLanguage: coordinator.preferredSubtitleLanguage
                ) { url in
                    guard coordinator.selectedURL == videoURL else { return }
                    draft.subtitleID = coordinator.registerExternalSubtitle(url)?.id
                }
            }
        }
        .onChange(of: coordinator.selectedURL) { _, _ in isPresented = false }
    }

    private func signed(_ value: Double) -> String {
        String(format: "%+.2f", value)
    }

    private var selectedAudio: Binding<String?> {
        Binding(
            get: { draft.audioID },
            set: { identifier in
                draft.audioID = identifier
                draft.audioOutputMode = .original
            }
        )
    }
}

struct NetworkBadge: View {
    var monitor: NetworkMonitor

    var body: some View {
        Label(L10n.text(monitor.summary), systemImage: monitor.symbol)
            .font(.caption.weight(.semibold))
            .foregroundStyle(monitor.isReady ? .green : .orange)
    }
}

struct MediaBadgeView: View {
    let badge: MediaBadge

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(L10n.text(badge.label).uppercased())
                .font(.system(size: 9.5, weight: .bold))
                .tracking(0.75)
                .foregroundStyle(.tertiary)
            Text(L10n.text(badge.value))
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(L10n.text(badge.detail))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(minWidth: 112, alignment: .leading)
    }
}

struct PlanRow: View {
    let symbol: String
    let text: String
    let warning: Bool

    var body: some View {
        Label(L10n.text(text), systemImage: warning ? "exclamationmark.triangle.fill" : symbol)
            .foregroundStyle(warning ? .orange : .secondary)
    }
}

struct LibraryEmptyView: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30))
            Text(L10n.text(text))
                .font(.callout)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.tertiary)
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player { nsView.player = player }
    }
}

struct AirPlayDevicePicker: View {
    var controller: AirPlayController

    var body: some View {
        Menu {
            if controller.devices.isEmpty {
                Text(L10n.text(controller.isScanning ? "Buscando…" : "No se encontró ningún Apple TV"))
            } else {
                ForEach(controller.devices) { device in
                    Button {
                        Task { await controller.selectDevice(device.id) }
                    } label: {
                        Label(
                            device.name,
                            systemImage: controller.selectedDeviceID == device.id ? "checkmark.circle.fill" : "tv"
                        )
                    }
                    .help(device.detail)
                    .disabled(controller.isSessionActive)
                }
            }
            Divider()
            if controller.selectedDevice != nil {
                Button {
                    controller.beginPairing()
                } label: {
                    Label(
                        L10n.text(
                            controller.isCheckingAuthorization
                                ? "Comprobando autorización…"
                                : (controller.requiresPairing
                                    ? "Autorizar AirCiller…" : "Renovar autorización…")),
                        systemImage: "lock.open"
                    )
                }
                .disabled(controller.isCheckingAuthorization || controller.isSessionActive)
            }
            Button {
                Task { await controller.refreshDevices() }
            } label: {
                Label("Buscar Apple TV", systemImage: "arrow.clockwise")
            }
            .disabled(controller.isScanning || controller.isSessionActive)
        } label: {
            HStack(spacing: 7) {
                if controller.isScanning {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: controller.isConnected ? "airplayvideo.circle.fill" : "airplayvideo")
                        .foregroundStyle(controller.isConnected ? Color.airCillerYellow : .primary)
                }
                Text(controller.selectedDevice?.name ?? "Apple TV")
                    .lineLimit(1)
            }
        }
        .menuStyle(.button)
        .frame(minWidth: 128)
        .help(controller.selectedDevice?.detail ?? L10n.text(controller.status))
    }
}

struct AirPlayPairingView: View {
    var controller: AirPlayController
    @AirCillerState private var pin = ""

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "airplayvideo.circle.fill")
                .font(.system(size: 52, weight: .medium))
                .foregroundStyle(Color.airCillerYellow)

            VStack(spacing: 6) {
                Text("Autorizar AirCiller")
                    .font(.title2.bold())
                Text("El código pertenece al Apple TV y se procesa solo en este Mac.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            pairingContent

            HStack {
                Button("Cancelar") {
                    controller.cancelPairing()
                }
                Spacer()
                if case .waitingForPIN = controller.pairingState {
                    Button("Autorizar") {
                        let submittedPIN = pin
                        pin = ""
                        controller.submitPairingPIN(submittedPIN)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pin.count != 4)
                }
            }
        }
        .padding(26)
        .frame(width: 420)
        .frame(minHeight: 300)
        .onDisappear {
            if controller.pairingState != .success {
                controller.cancelPairing(closeSheet: false)
            }
        }
    }

    @ViewBuilder
    private var pairingContent: some View {
        switch controller.pairingState {
        case .idle, .starting:
            VStack(spacing: 10) {
                ProgressView()
                Text("Pidiendo un código al Apple TV…")
                    .foregroundStyle(.secondary)
            }
        case .waitingForPIN:
            VStack(spacing: 10) {
                Text("Introduce el código de 4 cifras que aparece en la televisión")
                    .font(.callout.weight(.semibold))
                SecureField("Código", text: pinBinding)
                    .textFieldStyle(.roundedBorder)
                    .font(.title2.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(width: 130)
                    .onSubmit {
                        guard pin.count == 4 else { return }
                        let submittedPIN = pin
                        pin = ""
                        controller.submitPairingPIN(submittedPIN)
                    }
            }
        case .verifying:
            VStack(spacing: 10) {
                ProgressView()
                Text("Verificando con el Apple TV…")
                    .foregroundStyle(.secondary)
            }
        case .success:
            Label("Apple TV autorizado", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
        case .failed(let message):
            VStack(spacing: 9) {
                Label("No se pudo autorizar", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(L10n.text(message))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Volver a intentar") {
                    pin = ""
                    controller.retryPairing()
                }
            }
        }
    }

    private var pinBinding: Binding<String> {
        Binding(
            get: { pin },
            set: { value in
                pin = String(value.filter(\.isNumber).prefix(4))
            }
        )
    }
}

extension Color {
    static let airCillerYellow = Color(nsColor: .systemYellow)
}

extension String {
    var softWrappedFilename: String {
        replacingOccurrences(of: ".", with: ".\u{200B}")
            .replacingOccurrences(of: "-", with: "-\u{200B}")
            .replacingOccurrences(of: "_", with: "_\u{200B}")
    }
}

struct AirCillerBackdrop: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
    }
}

private struct AirCillerGlassControlModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.borderless)
            .padding(5)
            .contentShape(Rectangle())
    }
}

private struct PlaybackControlSurface: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        }
    }
}

private struct AirCillerContentCardModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                .regularMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.075), lineWidth: 1)
            }
    }
}

extension View {
    fileprivate func airCillerGlassControl() -> some View {
        modifier(AirCillerGlassControlModifier())
    }

    fileprivate func airCillerContentCard(cornerRadius: CGFloat) -> some View {
        modifier(AirCillerContentCardModifier(cornerRadius: cornerRadius))
    }
}
