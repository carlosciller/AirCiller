import SwiftUI

struct LibraryRecoveryView: View {
    var coordinator: StreamCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recuperación de biblioteca").font(.title2)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(coordinator.libraryRecoveryIssues) { issue in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(LibraryRecovery.collectionName(issue.collection)).font(.headline)
                            Text(LibraryRecovery.explanation(issue.problem))
                            if let checkpoint = issue.checkpoint {
                                Text(
                                    L10n.format(
                                        "Copia del %@",
                                        checkpoint.savedAt.formatted(date: .abbreviated, time: .shortened))
                                )
                                .foregroundStyle(.secondary)
                                Button("Restaurar copia…") {
                                    coordinator.confirmLibraryRestore(issue, useCheckpoint: true)
                                }
                                .disabled(!coordinator.canRestoreLibrary)
                            }
                            if issue.problem == .malformedData || issue.problem == .unrecognizedFormat {
                                Button("Empezar esta lista vacía…") {
                                    coordinator.confirmLibraryRestore(issue, useCheckpoint: false)
                                }
                                .disabled(!coordinator.canRestoreLibrary)
                            }
                        }
                        Divider()
                    }
                    if !coordinator.libraryRecoveryMessage.isEmpty {
                        Text(coordinator.libraryRecoveryMessage)
                    }
                    if !coordinator.canRestoreLibrary {
                        Text("Detén la reproducción o espera a que termine la operación antes de restaurar.")
                    }
                    Text(
                        "Las copias contienen listas y progreso, no películas. Se guarda una copia válida y hasta dos fallos por lista, con un máximo total de 36 MiB."
                    )
                    .font(.callout).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button("Mostrar copias en Finder") { coordinator.showLibraryRecoveryFiles() }
                Button("Reintentar") { coordinator.refreshLibraryRecovery() }
                Spacer()
                Button("Cerrar") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 540, height: 420)
    }
}
