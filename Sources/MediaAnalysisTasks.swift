import Foundation

/// Owns the two analyses associated with the currently selected movie.
/// Keeping them together makes Stop and file changes cancel both jobs.
@MainActor
final class MediaAnalysisTasks {
    private(set) var primary: Task<Void, Never>?
    private(set) var demand: Task<Void, Never>?
    private var retiringDemand: Task<Void, Never>?
    private var retirementID: UUID?

    func replacePrimary(with task: Task<Void, Never>) {
        primary?.cancel()
        primary = task
    }

    func replaceDemand(with task: Task<Void, Never>) {
        cancelDemand()
        demand = task
    }

    func cancelAll() {
        primary?.cancel()
        cancelDemand()
        primary = nil
    }

    @discardableResult
    func cancelDemand() -> Task<Void, Never>? {
        guard let cancelled = demand else { return retiringDemand }
        cancelled.cancel()
        demand = nil
        let previous = retiringDemand
        let id = UUID()
        retirementID = id
        let retirement = Task { [weak self] in
            await previous?.value
            await cancelled.value
            guard let self, self.retirementID == id else { return }
            self.retiringDemand = nil
            self.retirementID = nil
        }
        retiringDemand = retirement
        return retirement
    }
}
