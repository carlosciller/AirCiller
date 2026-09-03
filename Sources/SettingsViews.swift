import AppKit
import SwiftUI
import UniformTypeIdentifiers

private typealias AirCillerState<Value> = SwiftUI.State<Value>

struct AirCillerSettingsView: View {
    @Bindable var coordinator: StreamCoordinator
    @Bindable var updateController: UpdateController
    @AirCillerState private var components = ComponentManager()

    var body: some View {
        TabView {
            PlaybackSettingsView(coordinator: coordinator)
                .tabItem {
                    Label("Reproducción", systemImage: "play.circle")
                }

            OpenSubtitlesSettingsView()
                .tabItem {
                    Label("Subtítulos online", systemImage: "captions.bubble")
                }

            StorageSettingsView(coordinator: coordinator)
                .tabItem {
                    Label("Almacenamiento", systemImage: "internaldrive")
                }

            SupportSettingsView(coordinator: coordinator, components: components)
                .tabItem {
                    Label("Diagnóstico", systemImage: "stethoscope")
                }

            UpdateSettingsView(updateController: updateController)
                .tabItem {
                    Label("Actualizaciones", systemImage: "arrow.triangle.2.circlepath")
                }
        }
        .frame(width: 640, height: 500)
    }
}

struct SupportSettingsView: View {
    @Bindable var coordinator: StreamCoordinator
    @Bindable var components: ComponentManager
    @AirCillerState private var showingResetConfirmation = false
    @AirCillerState private var operationMessage: String?

    private var playbackIsBusy: Bool {
        coordinator.isPreparing || coordinator.isStreaming
    }

    var body: some View {
        Form {
            Section("Informe local") {
                Text(
                    "Crea un archivo de texto sin nombres de películas, rutas personales, nombres o direcciones de receptores ni credenciales. No se envía automáticamente."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button("Exportar diagnóstico…") {
                    exportDiagnostics()
                }
            }

            Section {
                DisclosureGroup("Detalles del motor") {
                    if components.hasRefreshed {
                        engineStatus(.ffmpeg)
                        engineStatus(.airPlay)

                        if !engineIsReady {
                            Text(
                                "Esta copia de AirCiller está incompleta. Descarga de nuevo la aplicación para repararla."
                            )
                            .font(.caption)
                            .foregroundStyle(.orange)
                        }
                    } else {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Comprobando motor…")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(
                        "Los motores forman parte de esta versión de AirCiller y se actualizan junto con la app después de ser probados."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section {
                if let device = coordinator.airPlay.selectedDevice {
                    LabeledContent("Receptor", value: device.detail)
                } else {
                    LabeledContent("Receptor", value: "No seleccionado")
                }

                Button("Restablecer autorización…", role: .destructive) {
                    showingResetConfirmation = true
                }
                .disabled(coordinator.airPlay.selectedDevice == nil || playbackIsBusy)

                if let operationMessage {
                    Text(operationMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Apple TV")
            } footer: {
                Text(
                    "Solo elimina del Llavero la autorización del Apple TV seleccionado. La próxima reproducción pedirá un código nuevo una única vez."
                )
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .confirmationDialog(
            "¿Restablecer la autorización de este Apple TV?",
            isPresented: $showingResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Restablecer autorización", role: .destructive) {
                Task { await resetAuthorization() }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("AirCiller volverá a pedir el código de cuatro cifras al intentar reproducir.")
        }
        .task {
            await components.refresh()
        }
    }

    private var engineIsReady: Bool {
        ManagedComponent.allCases.allSatisfy { components.status(for: $0).isCompatible }
    }

    @ViewBuilder
    private func engineStatus(_ component: ManagedComponent) -> some View {
        let status = components.status(for: component)
        LabeledContent(component.title) {
            HStack(spacing: 6) {
                if let version = status.version {
                    Text(version)
                        .foregroundStyle(.secondary)
                }
                Image(systemName: status.isCompatible ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(status.isCompatible ? .green : .orange)
                    .accessibilityLabel(status.isCompatible ? Text("Listo") : Text("Instalación incompleta"))
            }
        }
    }

    private func resetAuthorization() async {
        do {
            try await coordinator.airPlay.resetSelectedDeviceAuthorization()
            operationMessage = L10n.text("La autorización se ha eliminado correctamente.")
        } catch {
            operationMessage = L10n.format("No se pudo restablecer la autorización: %@", error.localizedDescription)
        }
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.title = L10n.text("Exportar diagnóstico")
        panel.prompt = L10n.text("Guardar")
        panel.nameFieldStringValue = "AirCiller-Diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try diagnosticsReport.write(to: url, atomically: true, encoding: .utf8)
            operationMessage = L10n.text("Diagnóstico guardado.")
        } catch {
            operationMessage = L10n.format("No se pudo guardar el diagnóstico: %@", error.localizedDescription)
        }
    }

    private var diagnosticsReport: String {
        let bundle = Bundle.main
        let probe = coordinator.probeInfo
        let receiver = coordinator.airPlay.selectedDevice
        let ffmpeg = components.status(for: .ffmpeg)
        let airPlay = components.status(for: .airPlay)
        let playbackState =
            coordinator.isPreparing
            ? "preparing"
            : coordinator.isStreaming
                ? (coordinator.isPlaying ? "playing" : "paused")
                : "idle"
        let snapshot = DiagnosticsReportSnapshot(
            appVersion: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?",
            appBuild: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?",
            systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: Self.architecture,
            appLanguage: L10n.locale.identifier,
            playbackState: playbackState,
            playbackRoute: coordinator.diagnosticPlaybackRoute,
            currentTime: coordinator.currentTime,
            duration: coordinator.duration,
            rebufferEvents: coordinator.rebufferEvents,
            networkReady: coordinator.network.isReady,
            videoCodec: probe?.videoCodec,
            videoDimensions: probe.flatMap { probe in
                guard let width = probe.width, let height = probe.height else { return nil }
                return "\(width)x\(height)"
            },
            dolbyVisionProfile: probe?.dolbyVisionProfile,
            hdr: probe?.isHDR ?? false,
            audioCodec: coordinator.selectedAudio?.codec,
            audioMode: coordinator.selectedAudio.map { _ in coordinator.audioOutputMode.rawValue },
            subtitleCodec: coordinator.selectedSubtitle?.codec,
            subtitleKind: coordinator.selectedSubtitle.map { subtitle in
                if subtitle.isDescribedAsForced { return "forced" }
                return subtitle.isDescribedAsSDH ? "sdh" : "standard"
            },
            receiverModel: receiver?.model,
            receiverSystem: receiver.map { $0.osVersion.isEmpty ? "unknown" : "tvOS \($0.osVersion)" },
            receiverProtocol: receiver?.protocolVersion,
            authorizationState: authorizationDescription,
            ffmpegVersion: ffmpeg.version,
            ffmpegSource: ffmpeg.source,
            airPlayVersion: airPlay.version,
            airPlaySource: airPlay.source
        )
        return DiagnosticsReport.render(snapshot)
    }

    private var authorizationDescription: String {
        switch coordinator.airPlay.authorizationState {
        case .unknown: return "unknown"
        case .checking: return "checking"
        case .authorized: return "authorized"
        case .required: return "required"
        }
    }

    private static var architecture: String {
        #if arch(arm64)
            return "arm64"
        #elseif arch(x86_64)
            return "x86_64"
        #else
            return "unknown"
        #endif
    }
}

struct UpdateSettingsView: View {
    @Bindable var updateController: UpdateController

    private var appVersion: String {
        let version =
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return L10n.format("%@ (compilación %@)", version, build)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("AirCiller", value: appVersion)
                LabeledContent(
                    "Motor de actualizaciones",
                    value: "Sparkle \(UpdateController.sparkleVersion)"
                )
                LabeledContent("Estado") {
                    Label(
                        updateController.isConfigured ? "Listo" : "No configurado",
                        systemImage: updateController.isConfigured
                            ? "checkmark.circle.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(updateController.isConfigured ? .green : .orange)
                }
                if let feedHost = updateController.feedHost {
                    LabeledContent("Servidor", value: feedHost)
                }
            }

            Section {
                Toggle(
                    "Buscar actualizaciones automáticamente",
                    isOn: Binding(
                        get: { updateController.automaticallyChecksForUpdates },
                        set: { updateController.setAutomaticallyChecksForUpdates($0) }
                    )
                )
                .disabled(!updateController.isStarted)

                Button("Buscar actualizaciones…") {
                    updateController.checkForUpdates()
                }
                .disabled(!updateController.canCheckForUpdates)
            } footer: {
                Text(
                    updateController.isPlaybackBusy
                        ? "Las actualizaciones se aplazan mientras AirCiller prepara o reproduce una película."
                        : updateController.isConfigured
                            ? "Las comprobaciones usan HTTPS y firmas EdDSA. AirCiller siempre pide confirmación antes de instalar."
                            : "Esta compilación local todavía necesita la URL HTTPS del appcast y la clave pública EdDSA."
                )
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .onAppear {
            updateController.refreshPreferences()
        }
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

                Picker(
                    "Tipo de subtítulo",
                    selection: Binding(
                        get: { coordinator.preferredSubtitleKind },
                        set: { coordinator.setPreferredSubtitleKind($0) }
                    )
                ) {
                    ForEach(SubtitleTrackPreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                .disabled(coordinator.preferredSubtitleLanguage.isEmpty)

                Text(coordinator.preferredSubtitleKind.explanation)
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

struct StorageSettingsView: View {
    var coordinator: StreamCoordinator
    @AirCillerState private var cacheLimitMB = AirCillerStorage.subtitleCacheLimitMB
    @AirCillerState private var snapshot = AirCillerStorage.snapshot()

    var body: some View {
        Form {
            Section("Subtítulos en caché") {
                LabeledContent("Caché local") {
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
                    "Guarda los WebVTT creados por Apple Vision y los subtítulos que descargas expresamente. Las imágenes temporales se borran y la película original nunca se modifica."
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
