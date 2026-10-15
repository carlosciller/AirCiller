import Foundation

/// Receiver controls use presentation time; history and chapter locations use
/// the original movie clock. A held opening must not move the saved movie point.
struct MoviePlaybackTimeline: Sendable {
    let sourceDuration: Double
    let presentationDuration: Double
    let videoContentOffset: Double

    func sourcePosition(forPresentation position: Double) -> Double {
        guard position.isFinite else { return 0 }
        return min(sourceDuration, max(0, position - videoContentOffset))
    }

    func presentationPosition(forSource position: Double) -> Double {
        guard position.isFinite, position > 0 else { return 0 }
        return min(presentationDuration, min(sourceDuration, position) + videoContentOffset)
    }
}
