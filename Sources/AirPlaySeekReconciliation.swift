import Foundation

/// Keeps replies from an earlier seek from becoming the base of the next skip.
/// The receiver remains authoritative after a bounded settling period.
struct AirPlaySeekReconciliation {
    private struct Request {
        let id: String
        let position: Double
        let issuedAt: TimeInterval
        var acknowledgedAt: TimeInterval?
    }

    private var pending: Request?

    mutating func begin(id: String, position: Double, now: TimeInterval) {
        pending = Request(id: id, position: position, issuedAt: now)
    }

    mutating func acknowledge(id: String?, position: Double, now: TimeInterval) -> Bool {
        guard let request = pending, request.id == id,
            request.acknowledgedAt == nil, position.isFinite,
            abs(position - request.position) < 0.001,
            now >= request.issuedAt, now - request.issuedAt < 10
        else { return false }
        pending?.acknowledgedAt = now
        return true
    }

    mutating func acceptsPosition(_ position: Double, now: TimeInterval) -> Bool {
        guard position.isFinite, position >= 0 else { return false }
        guard let request = pending else { return true }
        if now < request.issuedAt || now - request.issuedAt >= 10 {
            reset()
            return true
        }
        guard let acknowledgedAt = request.acknowledgedAt else { return false }
        if now - acknowledgedAt >= 2 {
            reset()
            return true
        }
        // Status events already in flight can follow the command reply. Keep
        // nearby receiver positions, but reject old destinations for at most
        // two seconds. This also bounds any delay in adopting a remote seek.
        return abs(position - request.position) <= 2
    }

    mutating func reset() {
        pending = nil
    }
}
