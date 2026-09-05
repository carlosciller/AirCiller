import SwiftUI

private typealias AirCillerState<Value> = SwiftUI.State<Value>

struct OpenSubtitlesSettingsView: View {
    @AirCillerState private var apiKey = ""
    @AirCillerState private var username = ""
    @AirCillerState private var password = ""
    @AirCillerState private var isWorking = false
    @AirCillerState private var message: String?
    @AirCillerState private var hasSavedConfiguration = false

    var body: some View {
        Form {
            Section {
                SecureField("Clave de API", text: $apiKey)
                    .textContentType(.password)
                TextField("Usuario (opcional)", text: $username)
                    .textContentType(.username)
                SecureField("Contraseña (opcional)", text: $password)
                    .textContentType(.password)

                Text(
                    "La cuenta aumenta el límite de descargas. La clave, el usuario y la contraseña se guardan juntos en el Llavero de este Mac."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack {
                    Button("Guardar y comprobar") {
                        Task { await saveAndTest() }
                    }
                    .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)

                    if isWorking {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Spacer()

                    if hasSavedConfiguration {
                        Button("Desconectar", role: .destructive) {
                            Task { await removeConfiguration() }
                        }
                        .disabled(isWorking)
                    }
                }

                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("OpenSubtitles.com")
            } footer: {
                Text(
                    "AirCiller busca solo cuando se lo pides. Envía a OpenSubtitles la huella y el tamaño del archivo, el idioma y, si no hay coincidencia exacta, el texto de búsqueda. Nunca envía la película."
                )
            }

            Section {
                Link(
                    "Abrir OpenSubtitles.com…",
                    destination: URL(string: "https://www.opensubtitles.com/")!
                )
                Link(
                    "Cómo crear una clave de API…",
                    destination: URL(
                        string:
                            "https://opensubtitles.stoplight.io/docs/opensubtitles-api/e3750fd63a100-getting-started"
                    )!
                )
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .task { await load() }
    }

    @MainActor
    private func load() async {
        do {
            guard let credentials = try await OpenSubtitlesService.shared.credentials() else { return }
            apiKey = credentials.apiKey
            username = credentials.username
            password = credentials.password
            hasSavedConfiguration = credentials.isConfigured
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func saveAndTest() async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            let credentials = OpenSubtitlesCredentials(
                apiKey: apiKey,
                username: username,
                password: password
            )
            try await OpenSubtitlesService.shared.saveCredentials(credentials)
            hasSavedConfiguration = true
            let downloads = try await OpenSubtitlesService.shared.testConnection()
            if let downloads {
                message = L10n.format(
                    "Conexión correcta. La cuenta permite %lld descargas al día.",
                    Int64(downloads)
                )
            } else {
                message = L10n.text("Conexión correcta. Se aplicará el límite sin cuenta.")
            }
        } catch {
            message = error.localizedDescription
        }
    }

    @MainActor
    private func removeConfiguration() async {
        isWorking = true
        message = nil
        defer { isWorking = false }
        do {
            try await OpenSubtitlesService.shared.removeCredentials()
            apiKey = ""
            username = ""
            password = ""
            hasSavedConfiguration = false
            message = L10n.text("La configuración se ha eliminado del Llavero.")
        } catch {
            message = error.localizedDescription
        }
    }
}

struct OpenSubtitlesSearchView: View {
    let videoURL: URL
    let onUse: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @AirCillerState private var query: String
    @AirCillerState private var language: String
    @AirCillerState private var results: [OpenSubtitlesSearchResult] = []
    @AirCillerState private var selectedID: String?
    @AirCillerState private var isWorking = false
    @AirCillerState private var isDownloading = false
    @AirCillerState private var message: String?
    @AirCillerState private var usedExactFileMatch = false
    @AirCillerState private var operationTask: Task<Void, Never>?

    init(
        videoURL: URL,
        preferredLanguage: String,
        onUse: @escaping (URL) -> Void
    ) {
        self.videoURL = videoURL
        self.onUse = onUse
        _query = AirCillerState(initialValue: Self.defaultQuery(for: videoURL))
        _language = AirCillerState(
            initialValue: preferredLanguage.isEmpty ? Self.defaultLanguage : preferredLanguage
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Buscar subtítulos")
                        .font(.title2.bold())
                    Text(videoURL.lastPathComponent.softWrappedFilename)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                TextField("Título de la película o episodio", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { beginNameSearch() }

                Picker("Idioma", selection: $language) {
                    Text("Cualquier idioma").tag("")
                    ForEach(LanguageNames.subtitlePreferenceOptions) { option in
                        Text(L10n.text(option.name)).tag(option.code)
                    }
                }
                .frame(width: 180)

                Button("Buscar") { beginNameSearch() }
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isWorking)
            }

            Group {
                if isWorking && results.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Buscando una coincidencia para este archivo…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    ContentUnavailableView {
                        Label("No hay resultados", systemImage: "captions.bubble")
                    } description: {
                        Text(message ?? L10n.text("Prueba con otro título o idioma."))
                    } actions: {
                        if message == OpenSubtitlesError.notConfigured.localizedDescription {
                            SettingsLink {
                                Text("Abrir Ajustes")
                            }
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 7) {
                        Label(
                            usedExactFileMatch
                                ? "Coincidencias exactas para este archivo"
                                : "Resultados por título",
                            systemImage: usedExactFileMatch ? "checkmark.seal.fill" : "magnifyingglass"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(usedExactFileMatch ? .green : .secondary)

                        List(results, selection: $selectedID) { result in
                            OpenSubtitlesResultRow(result: result)
                                .tag(result.id)
                        }
                        .listStyle(.inset)
                    }
                }
            }

            if let message, !results.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text(
                "La búsqueda es manual. AirCiller no sube el vídeo ni busca en segundo plano."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button("Cancelar") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button {
                    beginDownload()
                } label: {
                    if isDownloading {
                        HStack(spacing: 7) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Descargando…")
                        }
                    } else {
                        Text("Descargar y usar")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedResult == nil || isWorking)
            }
        }
        .padding(20)
        .frame(width: 760, height: 560)
        .task { await search(exactFirst: true) }
        .onDisappear { operationTask?.cancel() }
    }

    private var selectedResult: OpenSubtitlesSearchResult? {
        guard let selectedID else { return nil }
        return results.first(where: { $0.id == selectedID })
    }

    private func beginNameSearch() {
        guard !isWorking, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isWorking = true
        operationTask?.cancel()
        operationTask = Task { await search(exactFirst: false) }
    }

    private func beginDownload() {
        guard !isWorking, let result = selectedResult else { return }
        isWorking = true
        operationTask?.cancel()
        operationTask = Task { await download(result) }
    }

    @MainActor
    private func search(exactFirst: Bool) async {
        isWorking = true
        message = nil
        if !exactFirst {
            results = []
            selectedID = nil
        }
        defer { isWorking = false }
        do {
            let outcome =
                if exactFirst {
                    try await OpenSubtitlesService.shared.search(
                        videoURL: videoURL,
                        query: query,
                        preferredLanguage: language
                    )
                } else {
                    try await OpenSubtitlesService.shared.searchByName(
                        query: query,
                        preferredLanguage: language
                    )
                }
            guard !Task.isCancelled else { return }
            results = outcome.results
            usedExactFileMatch = outcome.usedExactFileMatch
            selectedID = outcome.results.first?.id
            if outcome.results.isEmpty {
                message = L10n.text("Prueba con otro título o idioma.")
            }
        } catch {
            guard !Task.isCancelled else { return }
            results = []
            selectedID = nil
            message = error.localizedDescription
        }
    }

    @MainActor
    private func download(_ result: OpenSubtitlesSearchResult) async {
        isWorking = true
        isDownloading = true
        message = nil
        defer {
            isWorking = false
            isDownloading = false
        }
        do {
            let url = try await OpenSubtitlesService.shared.download(result)
            guard !Task.isCancelled else { return }
            onUse(url)
            dismiss()
        } catch {
            guard !Task.isCancelled else { return }
            message = error.localizedDescription
        }
    }

    private static func defaultQuery(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    private static var defaultLanguage: String {
        L10n.locale.language.languageCode?.identifier == "es" ? "spa" : "eng"
    }
}

private struct OpenSubtitlesResultRow: View {
    let result: OpenSubtitlesSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(result.fileName)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(result.format)
                    .font(.caption2.monospaced().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
        .help(result.fileName)
    }

    private var details: String {
        var values = [LanguageNames.name(for: result.language)]
        if result.isTrusted { values.append(L10n.text("Fuente verificada")) }
        if result.isForced { values.append(L10n.text("Solo partes forzadas")) }
        if result.isHearingImpaired { values.append("SDH") }
        if result.isMachineTranslated || result.isAITranslated {
            values.append(L10n.text("Traducción automática"))
        }
        if !result.release.isEmpty { values.append(result.release) }
        values.append(L10n.format("%lld descargas", Int64(result.downloadCount)))
        return values.joined(separator: " · ")
    }
}
