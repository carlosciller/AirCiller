import Foundation

/// Only the most recent Play request may continue after an asynchronous
/// Keychain read or receiver authorization. Stop invalidates that request.
@MainActor
final class PlaybackAuthorizationPreflight {
    private var task: Task<Void, Never>?
    private var requestID: UUID?

    func start(
        operation: @escaping @MainActor () async throws -> Void,
        onSuccess: @escaping @MainActor () -> Void,
        onFailure: @escaping @MainActor (Error) -> Void
    ) {
        cancel()
        let id = UUID()
        requestID = id
        task = Task { [weak self] in
            do {
                try Task.checkCancellation()
                try await operation()
                try Task.checkCancellation()
                guard let self, self.requestID == id else { return }
                self.task = nil
                self.requestID = nil
                onSuccess()
            } catch {
                guard !Task.isCancelled, let self, self.requestID == id else { return }
                self.task = nil
                self.requestID = nil
                if !(error is CancellationError) { onFailure(error) }
            }
        }
    }

    func cancel() {
        requestID = nil
        task?.cancel()
        task = nil
    }
}
