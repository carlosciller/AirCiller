import Darwin
import Foundation
import Observation
import SwiftUI

/// Provisioned locally, never exported with settings or diagnostic reports.
enum PrivateRemoteConfigurationStore {
    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AirCiller/PrivateRemote/client.json")
    }

    static func load(from url: URL = Self.url) throws -> PrivateRemoteConfiguration {
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw CocoaError(.fileReadNoPermission) }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid(),
            info.st_mode & S_IFMT == S_IFREG, info.st_mode & 0o077 == 0,
            info.st_size > 0, info.st_size <= 16_384
        else { throw CocoaError(.fileReadNoPermission) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
        let data = try handle.read(upToCount: 16_385) ?? Data()
        guard data.count <= 16_384 else { throw CocoaError(.fileReadTooLarge) }
        let configuration = try JSONDecoder().decode(PrivateRemoteConfiguration.self, from: data)
        try configuration.validate()
        return configuration
    }
}

@MainActor @Observable
final class PrivateRemoteSettings {
    private(set) var enabled = false
    private(set) var configurationAvailable = false
    private(set) var configurationError = false
    private var client: PrivateRemoteClient?
    private var started = false
    private let preferenceKey = "privateRemoteEnabled"

    var state: String { client?.connectionState ?? "disabled" }

    func start(coordinator: StreamCoordinator) {
        guard !started else { return }
        started = true
        configurationAvailable = FileManager.default.fileExists(atPath: PrivateRemoteConfigurationStore.url.path)
        if UserDefaults.standard.bool(forKey: preferenceKey) { setEnabled(true, coordinator: coordinator) }
    }

    func setEnabled(_ value: Bool, coordinator: StreamCoordinator) {
        // Disabling remote control does not stop the movie, but queued commands
        // from the previous connection must no longer affect it.
        coordinator.invalidateRemoteControlSession()
        client?.stop()
        client = nil
        enabled = false
        configurationError = false
        UserDefaults.standard.set(false, forKey: preferenceKey)
        guard value else { return }
        do {
            let configuration = try PrivateRemoteConfigurationStore.load()
            let connection = try PrivateRemoteClient(configuration: configuration, coordinator: coordinator)
            client = connection
            connection.start()
            enabled = true
            configurationAvailable = true
            UserDefaults.standard.set(true, forKey: preferenceKey)
        } catch {
            configurationError = true
        }
    }
}

struct PrivateRemoteSettingsView: View {
    @Bindable var remote: PrivateRemoteSettings
    let coordinator: StreamCoordinator

    var body: some View {
        Form {
            Section {
                Toggle(
                    "Control privado con Dot",
                    isOn: Binding(
                        get: { remote.enabled },
                        set: { remote.setEnabled($0, coordinator: coordinator) }))
                LabeledContent("Estado") {
                    Text(L10n.text(statusText))
                }
            } footer: {
                Text(
                    "Comparte órdenes, títulos y estado con tu conexión privada. No envía películas, audio ni subtítulos. AirCiller debe permanecer abierta y el Mac despierto."
                )
            }
            if remote.configurationError {
                Text(
                    "No se pudo abrir la configuración privada. Reinstala la conexión; no cambies los permisos del Llavero."
                )
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var statusText: String {
        switch remote.state {
        case "connecting": "Conectando"
        case "connected": "Conectado"
        case "unavailable": "Conexión no disponible"
        default: "Desactivado"
        }
    }
}
