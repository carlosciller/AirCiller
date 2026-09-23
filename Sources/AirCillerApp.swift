import AppKit
import SwiftUI

// The macOS 27 command-line SDK exposes a State macro, but the lightweight
// Command Line Tools package does not ship SwiftUIMacros. Refer to the stable
// property-wrapper type explicitly so standalone builds do not depend on it.
private typealias AirCillerState<Value> = SwiftUI.State<Value>

#if !AIRCILLER_PLAYBACK_CHECKS
    @main
#endif
struct AirCillerApp: App {
    @NSApplicationDelegateAdaptor(AirCillerAppDelegate.self) private var appDelegate
    @AirCillerState private var coordinator = StreamCoordinator()

    var body: some Scene {
        Window("AirCiller", id: "main") {
            ContentView(coordinator: coordinator, appDelegate: appDelegate)
                .frame(minWidth: 720, minHeight: 520)
        }
        .defaultSize(width: 960, height: 650)
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
                .disabled(!coordinator.commandAvailability.canTogglePlayback)
                Button("Retroceder 10 segundos") { coordinator.skip(by: -10) }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                    .disabled(!coordinator.commandAvailability.canSeek)
                Button("Avanzar 10 segundos") { coordinator.skip(by: 10) }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
                    .disabled(!coordinator.commandAvailability.canSeek)
                Button("Retroceder 30 segundos") { coordinator.skip(by: -30) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                    .disabled(!coordinator.commandAvailability.canSeek)
                Button("Avanzar 30 segundos") { coordinator.skip(by: 30) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                    .disabled(!coordinator.commandAvailability.canSeek)
                Divider()
                Button("Detener") { coordinator.stop() }
                    .keyboardShortcut(".", modifiers: .command)
                    .disabled(!coordinator.commandAvailability.canStop)
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
        #if !AIRCILLER_PLAYBACK_CHECKS && !AIRCILLER_UI_CHECKS
            updateController.start()
        #endif
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
                    ForEach(coordinator.mediaBadges) { badge in
                        PlaybackInformationRow(
                            title: badge.label,
                            value: "\(L10n.text(badge.value)) · \(L10n.text(badge.detail))"
                        )
                    }
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
    @Binding var selectedRecentID: String?
    @AirCillerState private var confirmingClearQueue = false
    @AirCillerState private var confirmingClearRecent = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Tu biblioteca", selection: $selectedTab) {
                ForEach(LibraryTab.allCases) { tab in
                    Text(L10n.text(tab.rawValue)).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .padding(.horizontal, 13)
            .padding(.top, 12)
            .padding(.bottom, 8)

            HStack {
                Text(selectedTab == .playlist ? "Películas" : "Reproducidas recientemente")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
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
        .alert("¿Vaciar la playlist?", isPresented: $confirmingClearQueue) {
            Button("Cancelar", role: .cancel) {}
            Button("Vaciar", role: .destructive) { coordinator.clearQueue() }
        } message: {
            Text("Se quitarán todas las entradas de la playlist. Los archivos originales no se borrarán.")
        }
        .alert("¿Borrar el historial?", isPresented: $confirmingClearRecent) {
            Button("Cancelar", role: .cancel) {}
            Button("Borrar historial", role: .destructive) { coordinator.clearRecent() }
        } message: {
            Text(
                "Se eliminarán las entradas de Recientes y sus posiciones guardadas. Los archivos originales no se borrarán."
            )
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
                            HStack(alignment: .top) {
                                Text(item.title.softWrappedFilename)
                                    .font(.callout.weight(.medium))
                                    .lineLimit(2)
                                    .truncationMode(.tail)
                                    .frame(minHeight: 34, alignment: .topLeading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if coordinator.unavailableLibraryPaths.contains(item.path) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundStyle(.secondary)
                                        .help(L10n.text("Archivo no disponible"))
                                        .accessibilityLabel(L10n.text("Archivo no disponible"))
                                }
                            }
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
                        Button("Localizar archivo…") { coordinator.locateLibraryFile(item.url) }
                        Divider()
                        Button("Quitar de Recientes", role: .destructive) { coordinator.removeRecent(item) }
                    }
                } primaryAction: { ids in
                    if let item = coordinator.recentItems.first(where: { ids.contains($0.id) }) {
                        coordinator.playRecent(item)
                    }
                }
                Button("Borrar historial", role: .destructive) { confirmingClearRecent = true }
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
                    Label("Añadir película…", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !coordinator.queueItems.isEmpty {
                    Button {
                        confirmingClearQueue = true
                    } label: {
                        Label("Vaciar", systemImage: "trash").labelStyle(.iconOnly)
                    }
                    .help("Vaciar")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .padding(15)
        }
        .frame(maxHeight: .infinity)
    }
}

struct PlaylistMediaRow: View {
    let index: Int
    let item: QueueMediaItem
    let isCurrentMedia: Bool
    let isSelected: Bool
    var isUnavailable = false

    var body: some View {
        HStack(spacing: 6) {
            HStack(alignment: .center, spacing: 9) {
                Group {
                    if isUnavailable {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(
                                isSelected ? Color(nsColor: .alternateSelectedControlTextColor) : Color.secondary
                            )
                            .help(L10n.text("Archivo no disponible"))
                            .accessibilityLabel(L10n.text("Archivo no disponible"))
                    } else if isCurrentMedia {
                        Image(systemName: "film")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(
                                isSelected
                                    ? Color(nsColor: .alternateSelectedControlTextColor)
                                    : Color.primary
                            )
                            .accessibilityLabel("Película de la sesión actual")
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
    @AirCillerState private var showingSynchronization = false
    @AirCillerState private var showingAudioOptions = false
    @AirCillerState private var showingSubtitleOptions = false
    @AirCillerState private var draft: TrackSettings
    @AirCillerState private var original: TrackSettings
    private let videoURL: URL?

    init(coordinator: StreamCoordinator, isPresented: Binding<Bool>) {
        self.coordinator = coordinator
        _isPresented = isPresented
        _original = AirCillerState(initialValue: coordinator.trackSettings)
        _draft = AirCillerState(initialValue: coordinator.trackSettings)
        videoURL = coordinator.selectedURL
    }

    private var selectedSubtitle: SubtitleTrack? {
        coordinator.subtitleTracks.first { $0.id == draft.subtitleID }
    }

    private var canApply: Bool {
        draft.canApply(
            replacing: original,
            current: coordinator.trackSettings,
            sameMedia: coordinator.selectedURL == videoURL,
            controlsEnabled: coordinator.commandAvailability.canEditTracks
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Audio y subtítulos").font(.headline)
                Spacer()
                Button {
                    isPresented = false
                } label: {
                    Label("Cerrar", systemImage: "xmark")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.text("Cerrar"))
                .help(L10n.text("Cerrar"))
            }
            .padding(.horizontal, 18)
            .padding(.top, 21)
            .padding(.bottom, 7)
            Text(videoURL?.lastPathComponent.softWrappedFilename ?? "")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .textSelection(.enabled)
                .help(videoURL?.lastPathComponent ?? "")
                .accessibilityLabel(videoURL?.lastPathComponent ?? "")
                .padding(.horizontal, 18)
                .padding(.bottom, 10)
            Form {
                Section {
                    Picker("Audio", selection: selectedAudio) {
                        Text("Sin audio").tag(String?.none)
                        ForEach(coordinator.audioTracks) { track in
                            Text("\(L10n.text(track.displayName)) · \(L10n.text(track.technicalDescription))")
                                .tag(Optional(track.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .help(selectedAudioDescription)
                    .accessibilityValue(selectedAudioDescription)
                    Picker("Subtítulos", selection: $draft.subtitleID) {
                        Text("Desactivados").tag(String?.none)
                        ForEach(coordinator.subtitleTracks) { track in
                            Text(L10n.text(track.displayName)).tag(Optional(track.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .help(selectedSubtitle?.displayName ?? L10n.text("Desactivados"))
                    .accessibilityValue(selectedSubtitle?.displayName ?? L10n.text("Desactivados"))
                    if draft.audioID != nil && draft.audioOutputMode != .original {
                        Text(draft.audioOutputMode.explanation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let reason = selectedSubtitle?.unsupportedReason {
                        Label(L10n.text(reason), systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    } else if let notice = selectedSubtitle?.stylingNotice {
                        Text(L10n.text(notice))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DisclosureGroup("Sincronización", isExpanded: $showingSynchronization) {
                    delayControl("Audio (s)", value: $draft.audioDelay, range: -5...5, step: 0.05)
                    if draft.hasKnownAudioTimingLimitation(
                        isHDR: coordinator.probeInfo?.isHDR,
                        hasSelectedAudio: coordinator.audioTracks.contains { $0.id == draft.audioID }
                    ) {
                        Label(
                            "El ajuste de audio puede no aplicarse en esta película. La sincronización de subtítulos es independiente.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    delayControl("Subtítulos (s)", value: $draft.subtitleDelay, range: -10...10, step: 0.1)
                    Text("Un valor positivo retrasa la pista; uno negativo la adelanta.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DisclosureGroup("Opciones de audio", isExpanded: $showingAudioOptions) {
                    Picker("Formato de salida", selection: $draft.audioOutputMode) {
                        ForEach(AudioOutputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(draft.audioID == nil)
                    Text(draft.audioOutputMode.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DisclosureGroup("Opciones de subtítulos", isExpanded: $showingSubtitleOptions) {
                    Button {
                        if let track = coordinator.chooseExternalSubtitle() {
                            draft.subtitleID = track.id
                        }
                    } label: {
                        Label("Añadir archivo de subtítulos…", systemImage: "plus")
                    }
                    Button {
                        showingOpenSubtitles = true
                    } label: {
                        Label("Buscar en OpenSubtitles…", systemImage: "magnifyingglass")
                    }
                    .disabled(videoURL == nil)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text("SDH incluye diálogo, identificación del hablante y descripciones de sonidos o música.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .disabled(!coordinator.commandAvailability.canEditTracks)
            VStack(alignment: .leading, spacing: 12) {
                if draft == original {
                    Text("No hay cambios pendientes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if coordinator.isStreaming {
                    Text("La película se preparará con estas pistas y continuará desde la posición actual.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Los cambios se aplicarán al iniciar la reproducción.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Cancelar") { isPresented = false }
                        .keyboardShortcut(.cancelAction)
                    Button("Aplicar cambios") {
                        guard canApply else { return }
                        coordinator.trackSettings = draft
                        isPresented = false
                        coordinator.applyTrackSettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApply || selectedSubtitle?.isSelectable == false)
                }
            }
            .padding(18)
        }
        .sheet(isPresented: $showingOpenSubtitles) {
            if let videoURL {
                OpenSubtitlesSearchView(videoURL: videoURL, preferredLanguage: coordinator.preferredSubtitleLanguage) {
                    url in
                    guard coordinator.selectedURL == videoURL else { return }
                    draft.subtitleID = coordinator.registerExternalSubtitle(url)?.id
                }
            }
        }
        .onChange(of: coordinator.selectedURL) { _, _ in isPresented = false }
    }

    private var selectedAudioDescription: String {
        guard let track = coordinator.audioTracks.first(where: { $0.id == draft.audioID }) else {
            return L10n.text("Sin audio")
        }
        return "\(L10n.text(track.displayName)) · \(L10n.text(track.technicalDescription))"
    }

    private func delayControl(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double
    ) -> some View {
        LabeledContent {
            HStack(spacing: 6) {
                Stepper(value: value, in: range, step: step) {
                    Text(String(format: "%+.2f", value.wrappedValue))
                        .monospacedDigit()
                }
                .accessibilityLabel(L10n.text(title))
                Button {
                    value.wrappedValue = 0
                } label: {
                    Label("Restablecer", systemImage: "arrow.counterclockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .help("Restablecer")
                .disabled(value.wrappedValue == 0)
            }
        } label: {
            Text(L10n.text(title))
        }
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
                        .foregroundStyle(.primary)
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
