import Foundation

/// Owns the two analyses associated with the currently selected movie.
/// Keeping them together makes Stop and file changes cancel both jobs.
@MainActor
final class MediaAnalysisTasks {
    private(set) var primary: Task<Void, Never>?
    private(set) var demand: Task<Void, Never>?

    func replacePrimary(with task: Task<Void, Never>) {
        primary?.cancel()
        primary = task
    }

    func replaceDemand(with task: Task<Void, Never>) {
        demand?.cancel()
        demand = task
    }

    func cancelAll() {
        primary?.cancel()
        demand?.cancel()
        primary = nil
        demand = nil
    }
}
