import Combine
import Foundation
import Observation

/// Bridges Sparkle's KVO publisher into the observation used by menus and Settings.
@Observable
@MainActor
final class UpdateAvailability {
    private(set) var isAvailable = false
    @ObservationIgnored private var subscription: AnyCancellable?

    init(publisher: AnyPublisher<Bool, Never>) {
        subscription =
            publisher
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] available in
                MainActor.assumeIsolated {
                    self?.isAvailable = available
                }
            }
    }

    func allowsChecking(configured: Bool, started: Bool, playbackBusy: Bool) -> Bool {
        configured && !playbackBusy && (!started || isAvailable)
    }
}
