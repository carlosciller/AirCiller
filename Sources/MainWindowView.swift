import AppKit
import SwiftUI

private typealias WindowState<Value> = SwiftUI.State<Value>

/// The session and the library selection are deliberately independent.
struct ContentView: View {
    @Bindable var coordinator: StreamCoordinator
    let appDelegate: AirCillerAppDelegate
    @WindowState private var libraryTab: LibraryTab = .playlist
    @WindowState private var selectedRecentID: String?
    @WindowState private var showingTracks = false
    @WindowState private var trackEditingID = UUID()
    @WindowState private var showingStreamInfo = false
    @WindowState private var isScrubbing = false
    @WindowState private var scrubTime: Double = 0

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(
                coordinator: coordinator,
                selectedTab: $libraryTab,
                selectedRecentID: $selectedRecentID
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 380)
        } detail: {
            mainContent
                .background(.background)
                .inspector(isPresented: $showingTracks) {
                    // Keep the inspector's scrolling editor inside the split
                    // viewport; its intrinsic height must not resize every column.
                    GeometryReader { viewport in
                        TrackSettingsView(coordinator: coordinator, isPresented: $showingTracks)
                            .id(trackEditingID)
                            .frame(width: viewport.size.width, height: viewport.size.height)
                    }
                    .inspectorColumnWidth(min: 310, ideal: 340, max: 410)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        AirPlayDevicePicker(controller: coordinator.airPlay)
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            coordinator.chooseVideos()
                        } label: {
                            Label("Abrir película", systemImage: "plus")
                        }
                        .help("Abrir película")
                        Button {
                            coordinator.togglePlayback()
                        } label: {
                            Label(
                                coordinator.isPlaying ? "Pausa" : "Reproducir",
                                systemImage: coordinator.isPlaying ? "pause.fill" : "play.fill"
                            )
                        }
                        .help(L10n.text(coordinator.isPlaying ? "Pausa" : "Reproducir"))
                        .disabled(!coordinator.commandAvailability.canTogglePlayback)
                        Button {
                            coordinator.stop()
                        } label: {
                            Label("Detener", systemImage: "stop.fill")
                        }
                        .help("Detener")
                        .disabled(!coordinator.commandAvailability.canStop)
                    }
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button {
                            showingStreamInfo.toggle()
                        } label: {
                            Label("Información de reproducción", systemImage: "info.circle")
                        }
                        .help("Información de reproducción")
                        .disabled(coordinator.probeInfo == nil)
                        .popover(isPresented: $showingStreamInfo) {
                            PlaybackInformationView(coordinator: coordinator)
                        }
                        Button {
                            if showingTracks {
                                showingTracks = false
                            } else {
                                presentTracks()
                            }
                        } label: {
                            Label("Audio y subtítulos", systemImage: "sidebar.right")
                        }
                        .help("Audio y subtítulos")
                        .disabled(!showingTracks && !coordinator.commandAvailability.canEditTracks)
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
            appDelegate.installOpenHandler { coordinator.handleURLs($0) }
            synchronizeUpdateAvailability()
        }
        .onDisappear {
            appDelegate.removeOpenHandler()
            coordinator.stop(resetStatus: false)
        }
        .onChange(of: coordinator.isPreparing) { _, _ in synchronizeUpdateAvailability() }
        .onChange(of: coordinator.isStreaming) { _, _ in synchronizeUpdateAvailability() }
        .onChange(of: coordinator.isWaitingToStart) { _, _ in synchronizeUpdateAvailability() }
        .onChange(of: coordinator.isAnalyzing) { _, analyzing in
            synchronizeUpdateAvailability()
            if analyzing { showingTracks = false }
        }
        .onChange(of: coordinator.selectedURL) { _, _ in
            showingTracks = false
            isScrubbing = false
        }
        .dropDestination(for: URL.self) { urls, _ in
            coordinator.handleURLs(urls)
            return !urls.isEmpty
        }
    }

    private func synchronizeUpdateAvailability() {
        appDelegate.updateController.setPlaybackBusy(
            coordinator.isAnalyzing || coordinator.isWaitingToStart
                || coordinator.isPreparing || coordinator.isStreaming
        )
    }

    private func presentTracks() {
        trackEditingID = UUID()
        showingTracks = true
    }

    private var mainContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let url = coordinator.selectedURL {
                    sessionHeader(url)
                    session
                    if coordinator.probeInfo != nil {
                        trackSummary
                    }
                } else {
                    ContentUnavailableView {
                        Label("Elige una película", systemImage: "airplayvideo")
                    } description: {
                        Text("Abre una película o arrástrala aquí. AirCiller conserva el vídeo original.")
                    } actions: {
                        Button("Abrir película…") { coordinator.chooseVideos() }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(minHeight: 250)
                }
                if let selectedLibraryURL {
                    selectionDetail(selectedLibraryURL)
                }
            }
            .padding(24)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func sessionHeader(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(L10n.text(coordinator.status), systemImage: sessionSymbol)
                .font(.subheadline)
                .foregroundStyle(coordinator.hasError ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(url.deletingPathExtension().lastPathComponent.softWrappedFilename)
                .font(.title.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)
            if coordinator.probeInfo != nil {
                Text(
                    ([TimeFormatting.duration(coordinator.duration)]
                        + coordinator.mediaBadges
                        .filter { ["resolution", "dynamic-range"].contains($0.id) }
                        .map { L10n.text($0.value) })
                        .joined(separator: " · ")
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var session: some View {
        VStack(alignment: .leading, spacing: 20) {
            if coordinator.isAnalyzing {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    Text(L10n.text(coordinator.detail))
                        .foregroundStyle(.secondary)
                }
                Button("Cancelar") { coordinator.stop() }
            } else if coordinator.isPreparing {
                ProgressView(value: coordinator.preparationProgress)
                    .accessibilityLabel(Text(L10n.text(coordinator.status)))
                Text(L10n.text(coordinator.detail))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Cancelar") { coordinator.stop() }
            } else if coordinator.probeInfo == nil {
                Text(L10n.text(coordinator.detail))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = coordinator.selectedURL {
                    Button("Volver a analizar") { coordinator.loadVideo(url, autoStart: false) }
                }
            } else {
                if coordinator.hasError {
                    Text(L10n.text(coordinator.detail))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                transport
                if !coordinator.isStreaming {
                    Text(L10n.text(coordinator.detail))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if streamNeedsAttention {
                Button {
                    showingStreamInfo = true
                } label: {
                    Label("Revisa la conexión", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.link)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var transport: some View {
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                Spacer(minLength: 0)
                transportButton(
                    "Capítulo anterior", symbol: "backward.end.fill",
                    disabled: !coordinator.commandAvailability.canChangeChapter
                ) {
                    coordinator.previousChapter()
                }
                transportButton(
                    "Retroceder 10 segundos", symbol: "gobackward.10",
                    disabled: !coordinator.commandAvailability.canSeek
                ) {
                    coordinator.skip(by: -10)
                }
                Button {
                    coordinator.togglePlayback()
                } label: {
                    Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 30, weight: .medium))
                        .frame(width: 56, height: 52)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(coordinator.isPlaying ? Text("Pausa") : Text("Reproducir"))
                .help(L10n.text(coordinator.isPlaying ? "Pausa" : "Reproducir"))
                .disabled(!coordinator.commandAvailability.canTogglePlayback)
                transportButton(
                    "Avanzar 10 segundos", symbol: "goforward.10",
                    disabled: !coordinator.commandAvailability.canSeek
                ) {
                    coordinator.skip(by: 10)
                }
                transportButton(
                    "Capítulo siguiente", symbol: "forward.end.fill",
                    disabled: !coordinator.commandAvailability.canChangeChapter
                ) {
                    coordinator.nextChapter()
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubTime : coordinator.currentTime },
                        set: { scrubTime = $0 }
                    ),
                    in: 0...max(coordinator.duration, 1),
                    onEditingChanged: { editing in
                        if editing {
                            scrubTime = coordinator.currentTime
                            isScrubbing = true
                        } else {
                            isScrubbing = false
                            coordinator.seek(to: scrubTime)
                        }
                    }
                )
                .accessibilityLabel("Posición de reproducción")
                .accessibilityValue(
                    L10n.format(
                        "%@ de %@", TimeFormatting.duration(isScrubbing ? scrubTime : coordinator.currentTime),
                        TimeFormatting.duration(coordinator.duration))
                )
                .disabled(!coordinator.commandAvailability.canSeek)
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
        .padding(.vertical, 12)
    }

    private func transportButton(
        _ title: String, symbol: String, disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 28, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(L10n.text(title))
        .accessibilityLabel(L10n.text(title))
        .disabled(disabled)
    }

    private var trackSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
            Label(L10n.text(coordinator.audioPlan), systemImage: "speaker.wave.2")
                .fixedSize(horizontal: false, vertical: true)
            Label(L10n.text(coordinator.subtitlePlan), systemImage: "captions.bubble")
                .fixedSize(horizontal: false, vertical: true)
            Button("Audio y subtítulos…") { presentTracks() }
                .disabled(!coordinator.commandAvailability.canEditTracks)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private var selectedLibraryURL: URL? {
        if libraryTab == .playlist {
            return coordinator.queueItems.first { $0.id == coordinator.focusedQueueItemID }?.url
        }
        return coordinator.recentItems.first { $0.id == selectedRecentID }?.url
    }

    private func selectionDetail(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text("Selección en la biblioteca")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent.softWrappedFilename)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if url == coordinator.selectedURL {
                Text("Esta es la película de la sesión actual.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Button("Reproducir esta película") {
                    if libraryTab == .playlist,
                        let item = coordinator.queueItems.first(where: { $0.url == url })
                    {
                        coordinator.playQueueItem(item)
                    } else if let item = coordinator.recentItems.first(where: { $0.url == url }) {
                        coordinator.playRecent(item)
                    }
                }
                .disabled(coordinator.isPreparing || coordinator.isAnalyzing)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sessionSymbol: String {
        if coordinator.hasError { return "exclamationmark.triangle" }
        if coordinator.isAnalyzing { return "magnifyingglass" }
        if coordinator.isPreparing { return "hourglass" }
        if coordinator.isStreaming { return coordinator.isPlaying ? "airplayvideo" : "pause.circle" }
        return coordinator.probeInfo == nil ? "film" : "play.circle"
    }

    private var streamNeedsAttention: Bool {
        [.tight, .insufficient, .error].contains(coordinator.streamHealthLevel)
    }
}
