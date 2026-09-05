import Foundation

@main
struct AirPlaySeekReconciliationSmokeTest {
    static func main() {
        var state = AirPlaySeekReconciliation()
        var position = 100.0
        func request(_ id: String, by offset: Double, at time: Double) {
            position += offset
            state.begin(id: id, position: position, now: time)
        }
        func receiver(_ value: Double, at time: Double) {
            if state.acceptsPosition(value, now: time) { position = value }
        }
        func reply(_ id: String, _ value: Double, at time: Double) {
            if state.acknowledge(id: id, position: value, now: time) { position = value }
        }

        // Reproduce the physical +10, +10, -10, -10 burst with delayed replies
        // interleaved between clicks. It must return to the intended origin.
        request("first", by: 10, at: 0)
        request("second", by: 10, at: 0.2)
        reply("first", 110, at: 0.3)
        receiver(100.2, at: 0.35)
        precondition(position == 120)
        request("third", by: -10, at: 0.4)
        reply("second", 120, at: 0.45)
        receiver(100.4, at: 0.5)
        precondition(position == 110)
        request("fourth", by: -10, at: 0.6)
        reply("third", 110, at: 0.7)
        reply("fourth", 100, at: 0.8)
        receiver(120, at: 0.9)
        reply("fourth", 100, at: 1)  // Duplicate must not reset the settling deadline.
        precondition(position == 100)
        receiver(100.5, at: 1.2)
        precondition(position == 100.5)
        receiver(120, at: 1.3)
        precondition(position == 100.5)

        // Remote changes become authoritative after the bounded settling time.
        receiver(300, at: 2.81)
        precondition(position == 300)
        request("unanswered", by: 10, at: 3)
        receiver(301, at: 3.5)
        precondition(position == 310)
        receiver(305, at: 13)
        precondition(position == 305)
        reply("unanswered", 310, at: 14)
        precondition(position == 305)

        request("old-session", by: 10, at: 15)
        state.reset()
        receiver(0, at: 15.1)
        reply("old-session", 315, at: 15.2)
        precondition(position == 0)
        receiver(.nan, at: 16)
        receiver(.infinity, at: 16)
        receiver(-1, at: 16)
        precondition(position == 0)
        print("Seek bursts preserve the latest destination across delayed replies and status events: OK")
    }
}
