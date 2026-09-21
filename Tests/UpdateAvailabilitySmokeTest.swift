import Combine
import Foundation
import Observation

private final class UpdaterFixture: NSObject {
    @objc dynamic var canCheckForUpdates = false
}

private final class ChangeFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var changed = false

    func markChanged() { lock.withLock { changed = true } }
    var value: Bool { lock.withLock { changed } }
}

@main
struct UpdateAvailabilitySmokeTest {
    @MainActor static func main() async throws {
        let updater = UpdaterFixture()
        var availability: UpdateAvailability? = UpdateAvailability(
            publisher: updater.publisher(for: \.canCheckForUpdates).eraseToAnyPublisher()
        )
        weak var weakAvailability = availability
        precondition(availability!.allowsChecking(configured: true, started: false, playbackBusy: false))

        for expected in [true, false, true] {
            let change = ChangeFlag()
            withObservationTracking {
                _ = availability!.allowsChecking(configured: true, started: true, playbackBusy: false)
            } onChange: {
                change.markChanged()
            }
            updater.canCheckForUpdates = expected
            try await waitUntil {
                change.value && availability!.isAvailable == expected
            }
            precondition(
                availability!.allowsChecking(configured: true, started: true, playbackBusy: false) == expected
            )
            precondition(!availability!.allowsChecking(configured: true, started: true, playbackBusy: true))
            precondition(!availability!.allowsChecking(configured: false, started: true, playbackBusy: false))
        }

        availability = nil
        precondition(weakAvailability == nil, "The observation must not retain its owner")
        weakAvailability = nil
        updater.canCheckForUpdates = false

        let initiallyReady = UpdaterFixture()
        initiallyReady.canCheckForUpdates = true
        let ready = UpdateAvailability(
            publisher: initiallyReady.publisher(for: \.canCheckForUpdates).eraseToAnyPublisher()
        )
        try await waitUntil { ready.isAvailable }
        precondition(!ready.allowsChecking(configured: true, started: false, playbackBusy: true))
        precondition(!ready.allowsChecking(configured: false, started: false, playbackBusy: false))
        print("Update availability: KVO observation, repeated cycles, initial state, busy gates and cleanup: OK")
    }

    @MainActor private static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(2)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(condition(), "Update state did not notify its observer")
    }
}
