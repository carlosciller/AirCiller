import Foundation

/// All calls run on the app's main actor. Tests supply an isolated preferences
/// domain and directory; this service never opens media or credentials.
@MainActor
struct LibraryRecovery {
    typealias Collection = LibraryRecoveryArchive.Collection

    enum Problem: Equatable {
        case malformedData
        case unrecognizedFormat
        case archive(LibraryRecoveryArchive.Failure)
    }

    struct Issue: Identifiable {
        var id: Collection { collection }
        let collection: Collection
        let problem: Problem
        let expectedValue: Data
        let checkpoint: LibraryRecoveryArchive.Record?
    }

    enum Failure: Error {
        case changedSinceInspection
        case noValidCheckpoint
        case missingOriginal
    }

    let defaults: UserDefaults
    let archive: LibraryRecoveryArchive

    static func production() -> LibraryRecovery? {
        #if AIRCILLER_UI_CHECKS || AIRCILLER_PLAYBACK_CHECKS
            // Synthetic runners must opt in with their own temporary directory.
            return nil
        #else
            guard let domain = Bundle.main.bundleIdentifier,
                let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            else { return nil }
            return LibraryRecovery(
                defaults: .standard,
                archive: .init(
                    directory: support.appendingPathComponent(domain).appendingPathComponent("Library Recovery")))
        #endif
    }

    static func key(_ collection: Collection) -> String {
        switch collection {
        case .queue: HistoryStore.queueKey
        case .recent: HistoryStore.recentKey
        case .seasons: HistoryStore.seasonsKey
        }
    }

    static func collectionName(_ collection: Collection) -> String {
        switch collection {
        case .queue: L10n.text("Playlist")
        case .recent: L10n.text("Recientes")
        case .seasons: L10n.text("Temporadas")
        }
    }

    static func explanation(_ problem: Problem) -> String {
        switch problem {
        case .malformedData:
            L10n.text("No se pueden leer los datos guardados. Se ha conservado una copia del fallo.")
        case .unrecognizedFormat:
            L10n.text(
                "Esta versión no reconoce el formato guardado. Los datos se han conservado; comprueba si necesitas una versión más reciente de AirCiller."
            )
        case .archive(.unsupportedVersion):
            L10n.text("La copia usa una versión de recuperación no compatible. No se ha sustituido ningún dato.")
        case .archive(.permissionDenied):
            L10n.text(
                "No hay permiso para acceder a la carpeta de recuperación. Comprueba sus permisos en Finder y vuelve a intentarlo."
            )
        case .archive(.tooLarge):
            L10n.text(
                "Los datos superan el límite de recuperación de 4 MiB por archivo. Se conservan los datos actuales; no se ha recortado la lista."
            )
        case .archive(.occupiedIncident):
            L10n.text(
                "Hay otro fallo sin resolver. Se conservan ambos estados; revisa las copias antes de sustituir datos.")
        case .archive(.malformedRecord), .archive(.unsafeLocation):
            L10n.text(
                "La carpeta de recuperación contiene un archivo no válido. Revísala en Finder; no se ha sustituido ningún dato."
            )
        case .archive(.readFailed):
            L10n.text(
                "No se ha podido leer la copia de recuperación. Comprueba que la carpeta esté disponible y vuelve a intentarlo."
            )
        case .archive(.writeFailed):
            L10n.text(
                "No se ha podido guardar la copia de recuperación. Comprueba el espacio libre y vuelve a intentarlo. Los datos actuales siguen intactos."
            )
        }
    }

    /// Checkpoint on startup, not on every five-second progress update. An
    /// unresolved incident freezes its useful checkpoint. No fallback is saved.
    func inspect() -> [Issue] {
        Collection.allCases.compactMap { collection in
            let key = Self.key(collection)
            guard let value = defaults.object(forKey: key) else { return nil }
            let raw = originalRepresentation(value)
            guard let raw else {
                // UserDefaults values are property-list types; do not silently
                // interpret an unexpected representation as an empty library.
                return Issue(
                    collection: collection, problem: .unrecognizedFormat,
                    expectedValue: Data(), checkpoint: nil)
            }
            if let data = value as? Data, HistoryStore.validates(data, key: key) {
                do {
                    try archive.checkpoint(data, collection: collection)
                    return nil
                } catch {
                    return Issue(
                        collection: collection, problem: archiveProblem(error),
                        expectedValue: raw, checkpoint: nil)
                }
            }
            let problem: Problem =
                (value as? Data).flatMap { try? JSONSerialization.jsonObject(with: $0, options: .fragmentsAllowed) }
                    == nil && value is Data ? .malformedData : .unrecognizedFormat
            do {
                try archive.preserveIncident(raw, collection: collection)
                let stored = try archive.read(collection, slot: .checkpoint)
                let checkpoint = stored.flatMap {
                    HistoryStore.validates($0.payload, key: key) ? $0 : nil
                }
                return Issue(
                    collection: collection, problem: problem,
                    expectedValue: raw, checkpoint: checkpoint)
            } catch {
                return Issue(
                    collection: collection, problem: archiveProblem(error),
                    expectedValue: raw, checkpoint: nil)
            }
        }
    }

    /// Call only after the user confirms the specific collection and checkpoint
    /// date (or an empty list). Recheck the live value and checkpoint before use.
    func restore(_ issue: Issue, useCheckpoint: Bool) throws {
        let key = Self.key(issue.collection)
        guard let value = defaults.object(forKey: key), let raw = originalRepresentation(value) else {
            throw Failure.missingOriginal
        }
        guard raw == issue.expectedValue, !HistoryStore.canWrite(key, defaults: defaults) else {
            throw Failure.changedSinceInspection
        }
        let replacement: Data
        if useCheckpoint {
            guard let expected = issue.checkpoint,
                let current = try archive.read(issue.collection, slot: .checkpoint), current == expected,
                HistoryStore.validates(current.payload, key: key)
            else { throw Failure.noValidCheckpoint }
            replacement = current.payload
        } else {
            replacement = Data("[]".utf8)
        }
        // Preservation must succeed again before any live value is replaced.
        try archive.preserveIncident(raw, collection: issue.collection)
        // Marking precedes the preferences change. If the app stops here, the
        // next inspection sees the same bad bytes and reopens the incident.
        try archive.markResolved(raw, collection: issue.collection)
        defaults.set(replacement, forKey: key)
        // UserDefaults has no transactional disk-write acknowledgement. This
        // API changes preferences; it does not claim a durable disk commit.
    }

    private func originalRepresentation(_ value: Any) -> Data? {
        if let data = value as? Data { return data }
        return try? PropertyListSerialization.data(
            fromPropertyList: ["originalPreferenceValue": value], format: .binary, options: 0)
    }

    private func archiveProblem(_ error: Error) -> Problem {
        .archive((error as? LibraryRecoveryArchive.Failure) ?? .writeFailed)
    }
}
