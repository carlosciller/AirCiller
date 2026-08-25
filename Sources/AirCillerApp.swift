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
                Divider()
                Button("Detener") { coordinator.stop() }
                    .keyboardShortcut(".", modifiers: .command)
            }
        }

        Settings {
            AirCillerSettingsView(coordinator: coordinator)
        }
    }
}

final class AirCillerAppDelegate: NSObject, NSApplicationDelegate {
    private var pendingURLs: [URL] = []
    private var openHandler: (([URL]) -> Void)?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
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
        }
        .onDisappear {
            appDelegate.removeOpenHandler()
            coordinator.stop(resetStatus: false)
        }
        .dropDestination(for: URL.self) { urls, _ in
            coordinator.handleURLs(urls)
            return true
        }
    }

    private var mainContent: some View {
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

    private var header: some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.text(coordinator.selectedURL == nil ? "AIRPLAY 2" : "AHORA EN AIRCILLER"))
                    .font(.caption2.weight(.bold))
                    .tracking(1.25)
                    .foregroundStyle(Color.airCillerYellow)
                Text(displayTitle)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
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
                    .foregroundStyle(coordinator.airPlay.isConnected ? Color.airCillerYellow : .secondary)
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
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.22), radius: 28, y: 14)
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
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 16, y: 8)
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
        ZStack {
            HStack(spacing: 9) {
                Button {
                    coordinator.previousChapter()
                } label: {
                    Image(systemName: "backward.end.fill")
                }
                .airCillerGlassControl()
                .help("Capítulo anterior")
                .disabled(coordinator.chapters.isEmpty || coordinator.isPreparing)

                skipButton(seconds: -30, symbol: "gobackward.30")
                skipButton(seconds: -10, symbol: "gobackward.10")

                Button {
                    coordinator.togglePlayback()
                } label: {
                    Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 19, weight: .bold))
                        .frame(width: 46, height: 32)
                }
                .airCillerGlassControl()
                .disabled(coordinator.selectedURL == nil || coordinator.probeInfo == nil || coordinator.isPreparing)

                skipButton(seconds: 10, symbol: "goforward.10")
                skipButton(seconds: 30, symbol: "goforward.30")

                Button {
                    coordinator.nextChapter()
                } label: {
                    Image(systemName: "forward.end.fill")
                }
                .airCillerGlassControl()
                .help("Capítulo siguiente")
                .disabled(coordinator.chapters.isEmpty || coordinator.isPreparing)
            }

            HStack(spacing: 9) {
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

                Spacer()

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
                .foregroundStyle(coordinator.isStreaming || coordinator.isPreparing ? .red : .secondary)
                .disabled(!coordinator.isStreaming && !coordinator.isPreparing)
            }
        }
        .controlSize(.large)
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
            return coordinator.rebufferEvents > 0
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

struct AirCillerSettingsView: View {
    @Bindable var coordinator: StreamCoordinator
    @AirCillerState private var components = ComponentManager()

    var body: some View {
        TabView {
            PlaybackSettingsView(coordinator: coordinator)
                .tabItem {
                    Label("Reproducción", systemImage: "play.circle")
                }

            ComponentSettingsView(coordinator: coordinator, components: components)
                .tabItem {
                    Label("Componentes", systemImage: "shippingbox")
                }

            StorageSettingsView(coordinator: coordinator)
                .tabItem {
                    Label("Almacenamiento", systemImage: "internaldrive")
                }
        }
        .frame(width: 640, height: 500)
    }
}

struct PlaybackSettingsView: View {
    @Bindable var coordinator: StreamCoordinator

    var body: some View {
        Form {
            Section("Pistas predeterminadas") {
                Picker(
                    "Idioma de audio",
                    selection: Binding(
                        get: { coordinator.preferredAudioLanguage },
                        set: { coordinator.setPreferredAudioLanguage($0) }
                    )
                ) {
                    Text("Pista predeterminada del archivo").tag("")
                    ForEach(LanguageNames.subtitlePreferenceOptions) { option in
                        Text(L10n.text(option.name)).tag(option.code)
                    }
                }

                Text(
                    "Si el idioma no está disponible, AirCiller usa la pista marcada como predeterminada en el archivo."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Picker(
                    "Idioma de subtítulos",
                    selection: Binding(
                        get: { coordinator.preferredSubtitleLanguage },
                        set: { coordinator.setPreferredSubtitleLanguage($0) }
                    )
                ) {
                    Text("No activar automáticamente").tag("")
                    ForEach(LanguageNames.subtitlePreferenceOptions) { option in
                        Text(L10n.text(option.name)).tag(option.code)
                    }
                }

                Text(
                    "AirCiller prefiere una pista normal y usa SDH si es la única opción del idioma elegido."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Conversión") {
                Text(
                    "Estas preferencias solo eligen pistas. Si un audio necesita conversión, AirCiller seguirá explicando el motivo y pidiendo permiso para esa película."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }
}

struct ComponentSettingsView: View {
    var coordinator: StreamCoordinator
    @Bindable var components: ComponentManager

    private var playbackIsBusy: Bool {
        coordinator.isPreparing || coordinator.isStreaming
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Gestor") {
                    if let path = components.homebrewPath {
                        Text("Homebrew")
                            .help(path)
                    } else {
                        Text("No disponible")
                            .foregroundStyle(.secondary)
                    }
                }

                if components.isRefreshing {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Comprobando componentes…")
                            .foregroundStyle(.secondary)
                    }
                }

                if let message = components.operationMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        if components.activeComponent != nil {
                            ProgressView()
                                .progressViewStyle(.linear)
                        }
                        Text(L10n.text(message))
                        if let output = components.operationOutput, !output.isEmpty {
                            Text(output)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                                .textSelection(.enabled)
                        }
                        if components.activeComponent != nil {
                            Button("Cancelar") {
                                components.cancelOperation()
                            }
                        }
                    }
                }
            } footer: {
                Text(
                    "AirCiller no instala ni actualiza componentes por su cuenta. Homebrew descarga desde sus fuentes oficiales y muestra aquí el estado de la operación."
                )
            }

            ForEach(ManagedComponent.allCases) { component in
                componentSection(component)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .task {
            await components.refresh()
        }
    }

    @ViewBuilder
    private func componentSection(_ component: ManagedComponent) -> some View {
        let status = components.status(for: component)
        Section {
            LabeledContent("Estado") {
                Label(
                    status.isCompatible ? "Listo" : (status.isInstalled ? "Incompatible" : "No instalado"),
                    systemImage: status.isCompatible
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(status.isCompatible ? .green : .orange)
            }

            if let version = status.version {
                LabeledContent("Versión", value: version)
            }
            if let source = status.source {
                LabeledContent("Origen", value: source)
            }
            if let path = status.path {
                LabeledContent("Ubicación") {
                    Text(path)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(path)
                }
            }

            Text(L10n.text(component.purpose))
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(
                status.isInstalled && status.source == "Homebrew"
                    ? "Actualizar con Homebrew"
                    : "Instalar con Homebrew"
            ) {
                components.installOrUpdate(component)
            }
            .disabled(
                components.homebrewPath == nil
                    || components.activeComponent != nil
                    || playbackIsBusy
            )
        } header: {
            Text(component.title)
        } footer: {
            if playbackIsBusy {
                Text("Detén la reproducción antes de cambiar componentes.")
            }
        }
    }
}

struct StorageSettingsView: View {
    var coordinator: StreamCoordinator
    @AirCillerState private var cacheLimitMB = AirCillerStorage.subtitleCacheLimitMB
    @AirCillerState private var snapshot = AirCillerStorage.snapshot()

    var body: some View {
        Form {
            Section("Subtítulos gráficos") {
                LabeledContent("Caché OCR") {
                    Text(
                        L10n.format(
                            "%@ de %@",
                            byteCount(snapshot.subtitleCacheBytes),
                            byteCount(snapshot.subtitleCacheLimitBytes)
                        )
                    )
                    .monospacedDigit()
                }

                Picker("Límite", selection: $cacheLimitMB) {
                    ForEach(AirCillerStorage.subtitleCacheLimitOptionsMB, id: \.self) { megabytes in
                        Text(byteCount(Int64(megabytes) * 1_024 * 1_024)).tag(megabytes)
                    }
                }
                .onChange(of: cacheLimitMB) { _, newValue in
                    AirCillerStorage.setSubtitleCacheLimitMB(newValue)
                    refresh()
                }

                Text(
                    "Solo guarda el WebVTT creado por Apple Vision. Las imágenes temporales se borran y la película original nunca se modifica."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Vaciar caché de subtítulos", role: .destructive) {
                    try? AirCillerStorage.clearSubtitleCache()
                    refresh()
                }
                .disabled(snapshot.subtitleCacheBytes == 0)
            }

            Section("Preparación de películas") {
                LabeledContent("Restos temporales") {
                    Text(byteCount(snapshot.preparedMediaBytes))
                        .monospacedDigit()
                }
                Text(
                    "AirCiller conserva el paquete preparado solo mientras se reproduce y lo elimina al detener. Aquí puedes borrar restos de un cierre inesperado."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Eliminar restos temporales", role: .destructive) {
                    AirCillerStorage.clearPreparedMedia(
                        excluding: coordinator.activePreparedDirectory
                    )
                    refresh()
                }
                .disabled(snapshot.preparedMediaBytes == 0 || coordinator.isPreparing)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .task { refresh() }
    }

    private func refresh() {
        snapshot = AirCillerStorage.snapshot(
            excluding: coordinator.activePreparedDirectory
        )
    }

    private func byteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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

            VStack(spacing: 3) {
                LibraryNavigationRow(
                    title: "Playlist",
                    symbol: "play.square.stack.fill",
                    count: coordinator.queueItems.count,
                    isSelected: selectedTab == .playlist
                ) {
                    selectedTab = .playlist
                }
                LibraryNavigationRow(
                    title: "Recientes",
                    symbol: "clock.fill",
                    count: coordinator.recentItems.count,
                    isSelected: selectedTab == .recent
                ) {
                    selectedTab = .recent
                }
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 12)

            Divider()

            HStack {
                Text(L10n.text(selectedTab.rawValue))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
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
    }

    private var recentList: some View {
        VStack(spacing: 8) {
            if coordinator.recentItems.isEmpty {
                LibraryEmptyView(symbol: "clock.arrow.circlepath", text: "Aquí aparecerán las películas que abras")
            } else {
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(coordinator.recentItems) { item in
                            Button {
                                coordinator.openRecent(item)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(item.title.softWrappedFilename)
                                        .font(.callout.weight(.medium))
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
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
                                .padding(10)
                                .background(
                                    Color.primary.opacity(0.045),
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .overlay {
                                    if coordinator.selectedURL?.path == item.path {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(Color.airCillerYellow.opacity(0.72), lineWidth: 1.5)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help(item.title)
                            .contextMenu {
                                Button("Reproducir desde el inicio") {
                                    coordinator.playRecentFromBeginning(item)
                                }
                                Divider()
                                Button("Quitar de Recientes", role: .destructive) { coordinator.removeRecent(item) }
                            }
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.bottom, 6)
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
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 9) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 20, alignment: .trailing)
                    Text(item.title.softWrappedFilename)
                        .font(.callout.weight(.medium))
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if isSelected {
                    Label("Seleccionada", systemImage: "play.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.airCillerYellow)
                        .padding(.leading, 29)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 38)
                .contentShape(Rectangle())
                .accessibilityLabel("Arrastrar para ordenar")
        }
        .padding(10)
        .background(
            Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.airCillerYellow.opacity(0.72), lineWidth: 1.5)
            }
        }
        .help(item.title)
    }
}

struct LibraryNavigationRow: View {
    let title: String
    let symbol: String
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.airCillerYellow)
                    .frame(width: 20)
                Text(L10n.text(title))
                    .font(.callout.weight(.semibold))
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .airCillerSidebarSelection(isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }
}

struct TrackSettingsView: View {
    @Bindable var coordinator: StreamCoordinator
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pistas y sincronización")
                .font(.title3.bold())

            GroupBox("Audio") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Pista", selection: $coordinator.selectedAudioID) {
                        Text("Sin audio").tag(String?.none)
                        ForEach(coordinator.audioTracks) { track in
                            Text("\(L10n.text(track.displayName)) · \(L10n.text(track.technicalDescription))")
                                .tag(Optional(track.id))
                        }
                    }
                    Picker("Salida", selection: $coordinator.audioOutputMode) {
                        ForEach(AudioOutputMode.allCases) { mode in
                            Text(L10n.text(mode.title)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Stepper(value: $coordinator.audioDelay, in: -5...5, step: 0.05) {
                            Text(L10n.format("Sincronía: %@ s", signed(coordinator.audioDelay)))
                                .monospacedDigit()
                        }
                        Button("Restablecer") { coordinator.audioDelay = 0 }
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
                    Picker("Pista", selection: $coordinator.selectedSubtitleID) {
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
                        coordinator.addExternalSubtitle()
                    } label: {
                        Label("Añadir SRT, ASS o VTT…", systemImage: "plus")
                    }
                    .buttonStyle(.link)

                    if let reason = coordinator.selectedSubtitle?.unsupportedReason {
                        Label(L10n.text(reason), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if let notice = coordinator.selectedSubtitle?.stylingNotice {
                        Label(L10n.text(notice), systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Stepper(value: $coordinator.subtitleDelay, in: -10...10, step: 0.1) {
                            Text(L10n.format("Sincronía: %@ s", signed(coordinator.subtitleDelay)))
                                .monospacedDigit()
                        }
                        Button("Restablecer") { coordinator.subtitleDelay = 0 }
                            .font(.caption)
                    }
                    Text(
                        L10n.text(
                            coordinator.selectedSubtitle?.usesBitmapOCR == true
                                ? "El primer uso puede tardar mientras se reconoce la pista completa. El resultado queda en una caché local para las siguientes reproducciones."
                                : coordinator.selectedSubtitle?.usesAdvancedTextStyling == true
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
                Button("Aplicar pistas") {
                    isPresented = false
                    coordinator.applyTrackSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 620)
    }

    private func signed(_ value: Double) -> String {
        String(format: "%+.2f", value)
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
    fileprivate var softWrappedFilename: String {
        replacingOccurrences(of: ".", with: ".\u{200B}")
            .replacingOccurrences(of: "-", with: "-\u{200B}")
            .replacingOccurrences(of: "_", with: "_\u{200B}")
    }
}

struct AirCillerBackdrop: View {
    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            RadialGradient(
                colors: [
                    Color.airCillerYellow.opacity(0.105),
                    Color.airCillerYellow.opacity(0.018),
                    Color.clear,
                ],
                center: .topTrailing,
                startRadius: 18,
                endRadius: 720
            )
            LinearGradient(
                colors: [Color.white.opacity(0.035), Color.clear, Color.black.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct AirCillerGlassControlModifier: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

private struct AirCillerSidebarSelectionModifier: ViewModifier {
    let isSelected: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isSelected {
            if #available(macOS 26.0, *) {
                content.glassEffect(
                    .regular.interactive(),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
            } else {
                content.background(
                    Color.airCillerYellow.opacity(0.22),
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
            }
        } else {
            content
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

    fileprivate func airCillerSidebarSelection(isSelected: Bool) -> some View {
        modifier(AirCillerSidebarSelectionModifier(isSelected: isSelected))
    }

    fileprivate func airCillerContentCard(cornerRadius: CGFloat) -> some View {
        modifier(AirCillerContentCardModifier(cornerRadius: cornerRadius))
    }
}
