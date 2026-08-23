import Foundation

/// Keeps the Mac available while it is the HTTP source for an active AirPlay
/// session. Display sleep remains under the user's normal macOS settings.
@MainActor
final class PlaybackPowerAssertion {
    private var activity: NSObjectProtocol?

    var isActive: Bool { activity != nil }

    func begin() {
        guard activity == nil else { return }
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled],
            reason: L10n.text("AirCiller está preparando o enviando una película al Apple TV.")
        )
    }

    func end() {
        guard let activity else { return }
        ProcessInfo.processInfo.endActivity(activity)
        self.activity = nil
    }
}
