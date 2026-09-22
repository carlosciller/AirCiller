import AppKit
import SwiftUI

private typealias WindowState<Value> = SwiftUI.State<Value>

/// The session and the library selection are deliberately independent.
struct ContentView: View {
    @Bindable var coordinator: StreamCoordinator
    let appDelegate: AirCillerAppDelegate
    @Environment(\.undoManager) private var undoManager
    @WindowState private var libraryTab: LibraryTab = .playlist
    @WindowState private var showingTracks = false
    @WindowState private var trackEditingID = UUID()
    @WindowState private var showingStreamInfo = false
    @WindowState private var isScrubbing = false
    @WindowState private var scrubTime: Double = 0
    @FocusState private var focusedControl: Control?
    private enum Control: Hashable { case play, open, selection }

    var body: some View {
        NavigationSplitView {
            LibrarySidebar(
                coordinator: coordinator,
                selectedTab: $libraryTab,
                selectedRecentID: $coordinator.focusedRecentItemID
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 225, max: 310)
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
                    .inspectorColumnWidth(min: 245, ideal: 265, max: 310)
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
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
            coordinator.setLibraryUndoManager(undoManager)
            appDelegate.installOpenHandler { coordinator.handleURLs($0) }
            synchronizeUpdateAvailability()
        }
        .onDisappear {
            appDelegate.removeOpenHandler()
            coordinator.stop(resetStatus: false)
        }
        .onChange(of: undoManager) { _, manager in
            coordinator.setLibraryUndoManager(manager)
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
        .onChange(of: showingTracks) { _, shown in
            if !shown { focusedControl = coordinator.selectedURL == nil ? .open : .play }
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
            VStack(alignment: .leading, spacing: 0) {
                sessionHeader
                    .padding(.bottom, 28)
                session
                    .frame(maxWidth: .infinity, minHeight: 220)
                if let selectedLibraryURL {
                    Divider().padding(.top, 30).padding(.bottom, 16)
                    selectionDetail(selectedLibraryURL)
                }
            }
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var presentation: SessionPresentation {
        SessionPresentation(
            hasFile: coordinator.selectedURL != nil, hasProbe: coordinator.probeInfo != nil,
            hasError: coordinator.hasError, isAnalyzing: coordinator.isAnalyzing,
            isWaiting: coordinator.isWaitingToStart || coordinator.airPlay.authorizationState == .checking
                || coordinator.airPlay.isPairingPresented || coordinator.showConversionAlert,
            isPreparing: coordinator.isPreparing, isStreaming: coordinator.isStreaming,
            isPlaying: coordinator.isPlaying
        )
    }

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(sessionEyebrow)
                .font(.subheadline)
                .foregroundStyle(coordinator.hasError ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(
                coordinator.selectedURL?.deletingPathExtension().lastPathComponent.softWrappedFilename
                    ?? L10n.text("Elige tu próxima película")
            )
            .font(.system(size: 30, weight: .semibold))
            .tracking(-0.6)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityAddTraits(.isHeader)
            Text(sessionMetadata)
                .font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if coordinator.selectedAudio != nil,
                coordinator.audioOutputMode != .original || coordinator.selectedAudio?.canPassThrough == false
            {
                Text(L10n.text(coordinator.audioPlan))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sessionEyebrow: String {
        if coordinator.hasError { return L10n.text(coordinator.status) }
        switch presentation {
        case .empty:
            return L10n.text("Tu biblioteca, en Apple TV")
        case .ready:
            return L10n.text("Lista para reproducir")
        case .playing:
            return L10n.format("Reproduciendo en %@", coordinator.airPlay.selectedDevice?.name ?? "Apple TV")
        case .paused:
            return L10n.format("En pausa en %@", coordinator.airPlay.selectedDevice?.name ?? "Apple TV")
        case .unprepared, .analyzing, .waiting, .preparing, .error:
            return L10n.text(coordinator.status)
        }
    }

    private var sessionMetadata: String {
        guard coordinator.selectedURL != nil else {
            return L10n.text("Abre una película o arrástrala aquí.")
        }
        guard coordinator.probeInfo != nil else { return L10n.text(coordinator.detail) }
        var parts = coordinator.mediaBadges
            .filter { ["resolution", "dynamic-range"].contains($0.id) }
            .map { L10n.text($0.value) }
        if let audio = coordinator.selectedAudio {
            parts.append(
                [
                    audio.interpretedName, coordinator.audioOutputMode == .original ? L10n.text("Original") : nil,
                    audio.isAtmos ? "Atmos" : audio.channelDescription,
                ]
                .compactMap { $0 }.joined(separator: " ")
            )
        } else {
            parts.append(L10n.text("Sin audio"))
        }
        parts.append(
            coordinator.selectedSubtitle.map { L10n.format("Subtítulos: %@", $0.interpretedName) }
                ?? L10n.text("Sin subtítulos"))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var session: some View {
        VStack(spacing: 20) {
            switch presentation {
            case .empty:
                Image(systemName: "folder")
                    .font(.system(size: 38)).foregroundStyle(.tertiary).accessibilityHidden(true)
                Text("Tus películas se quedan en tus dispositivos.").foregroundStyle(.secondary)
                Button("Abrir película…") { coordinator.chooseVideos() }
                    .buttonStyle(.borderedProminent).focused($focusedControl, equals: .open)
            case .analyzing, .waiting, .preparing:
                if presentation == .preparing,
                    coordinator.preparationProgress > 0, coordinator.preparationProgress < 1
                {
                    ProgressView(value: coordinator.preparationProgress)
                        .frame(maxWidth: 360)
                        .accessibilityLabel(Text(L10n.text(coordinator.status)))
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(L10n.text(coordinator.status)).fontWeight(.medium)
                Text(L10n.text(coordinator.detail))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Cancelar") { coordinator.stop() }
                    .focused($focusedControl, equals: .play)
            case .unprepared, .error:
                Image(systemName: coordinator.hasError ? "exclamationmark.triangle" : "doc.text.magnifyingglass")
                    .font(.title).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(L10n.text(coordinator.detail))
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).frame(maxWidth: 360)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = coordinator.selectedURL {
                    if coordinator.probeInfo == nil {
                        Button("Volver a analizar") { coordinator.loadVideo(url, autoStart: false) }
                            .buttonStyle(.borderedProminent).focused($focusedControl, equals: .play)
                    } else {
                        Button("Reproducir en Apple TV") { coordinator.togglePlayback() }
                            .buttonStyle(.borderedProminent).focused($focusedControl, equals: .play)
                            .disabled(!coordinator.commandAvailability.canTogglePlayback)
                    }
                }
            case .ready:
                Label("Todo listo para preparar la reproducción", systemImage: "airplayvideo")
                    .foregroundStyle(.secondary)
                Button("Reproducir en Apple TV") { coordinator.togglePlayback() }
                    .buttonStyle(.borderedProminent).focused($focusedControl, equals: .play)
                    .disabled(!coordinator.commandAvailability.canTogglePlayback)
                if coordinator.currentTime > 0 {
                    Text(L10n.format("Continuar en %@", TimeFormatting.duration(coordinator.currentTime)))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                } else {
                    Text(TimeFormatting.duration(coordinator.duration))
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            case .playing, .paused:
                transport
                if coordinator.hasError {
                    Text(L10n.text(coordinator.detail))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).frame(maxWidth: 360)
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
    }

    private var transport: some View {
        VStack(spacing: 20) {
            Label(
                coordinator.isPlaying ? "La película se reproduce en Apple TV" : "Continúa cuando quieras",
                systemImage: coordinator.isPlaying ? "airplayvideo" : "pause"
            )
            .foregroundStyle(.secondary).font(.subheadline)
            timeline.frame(maxWidth: 440)
            if coordinator.chapters.isEmpty {
                transportControls
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 26) {
                        previousChapterButton
                        transportControls
                        nextChapterButton
                    }
                    VStack(spacing: 14) {
                        transportControls
                        HStack(spacing: 26) {
                            previousChapterButton
                            nextChapterButton
                        }
                    }
                }
            }
        }
    }

    private var transportControls: some View {
        HStack(spacing: 26) {
            transportButton(
                "Retroceder 10 segundos", symbol: "gobackward.10",
                disabled: !coordinator.commandAvailability.canSeek
            ) {
                coordinator.skip(by: -10)
            }
            playButton
            transportButton(
                "Avanzar 10 segundos", symbol: "goforward.10",
                disabled: !coordinator.commandAvailability.canSeek
            ) {
                coordinator.skip(by: 10)
            }
        }
    }

    private var previousChapterButton: some View {
        transportButton(
            "Capítulo anterior", symbol: "backward.end.fill",
            disabled: !coordinator.commandAvailability.canChangeChapter
        ) {
            coordinator.previousChapter()
        }
    }

    private var nextChapterButton: some View {
        transportButton(
            "Capítulo siguiente", symbol: "forward.end.fill",
            disabled: !coordinator.commandAvailability.canChangeChapter
        ) {
            coordinator.nextChapter()
        }
    }

    @ViewBuilder
    private var playButton: some View {
        if #available(macOS 26.0, *) {
            primaryTransportButton.buttonStyle(.glassProminent)
        } else {
            primaryTransportButton.buttonStyle(.borderedProminent)
        }
    }

    private var primaryTransportButton: some View {
        Button {
            coordinator.togglePlayback()
        } label: {
            Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                .font(.title3).frame(width: 26, height: 32)
        }
        .buttonBorderShape(.circle).controlSize(.large)
        .accessibilityLabel(coordinator.isPlaying ? Text("Pausa") : Text("Reproducir"))
        .help(L10n.text(coordinator.isPlaying ? "Pausa" : "Reproducir"))
        .focused($focusedControl, equals: .play)
        .disabled(!coordinator.commandAvailability.canTogglePlayback)
    }

    private var timeline: some View {
        VStack(spacing: 3) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubTime : coordinator.currentTime },
                    set: { scrubTime = $0 }
                ),
                in: 0...(coordinator.duration.isFinite ? max(coordinator.duration, 1) : 1),
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
                Text(TimeFormatting.duration(coordinator.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func transportButton(
        _ title: String, symbol: String, disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title2)
                .frame(width: 28, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(L10n.text(title))
        .accessibilityLabel(L10n.text(title))
        .disabled(disabled)
    }

    private var selectedLibraryURL: URL? {
        if libraryTab == .playlist {
            return coordinator.queueItems.first { $0.id == coordinator.focusedQueueItemID }?.url
        }
        return coordinator.recentItems.first { $0.id == coordinator.focusedRecentItemID }?.url
    }

    private func selectionDetail(_ url: URL) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 18) {
                selectionText(url)
                Spacer(minLength: 10)
                selectionButton(url)
            }
            VStack(alignment: .leading, spacing: 12) {
                selectionText(url)
                selectionButton(url)
            }
        }
    }

    private func selectionText(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Selección en la biblioteca")
                .font(.caption).foregroundStyle(.secondary)
            Text(url.lastPathComponent.softWrappedFilename)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private func selectionButton(_ url: URL) -> some View {
        Button(url == coordinator.selectedURL ? "Volver a la sesión" : "Reproducir esta película") {
            if url == coordinator.selectedURL {
                focusedControl = .play
            } else {
                if libraryTab == .playlist,
                    let item = coordinator.queueItems.first(where: { $0.url == url })
                {
                    coordinator.playQueueItem(item)
                } else if let item = coordinator.recentItems.first(where: { $0.url == url }) {
                    coordinator.playRecent(item)
                }
                focusedControl = .play
            }
        }
        .disabled(presentation.isBusy)
        .focused($focusedControl, equals: .selection)
    }

    private var streamNeedsAttention: Bool {
        [.tight, .insufficient, .error].contains(coordinator.streamHealthLevel)
    }
}
