import Foundation

@main
struct AirPlaySeekCoalescerSmokeTest {
    @MainActor static func main() async throws {
        var sent: [AirPlaySeekCoalescer.Request] = []
        var succeeds = true
        let queue = AirPlaySeekCoalescer { request in
            sent.append(request)
            return succeeds
        }
        for (index, position) in [25.0, 35, 25, 15].enumerated() {
            queue.enqueue(id: String(index), position: position)
        }
        precondition(sent.isEmpty)
        precondition(queue.flush())
        precondition(sent == [.init(id: "3", position: 15)])
        precondition(queue.flush() && sent.count == 1)
        queue.enqueue(id: "cancelled-session", position: 60)
        queue.cancel()
        precondition(queue.flush() && sent.count == 1)
        queue.enqueue(id: "new-session", position: 2)
        precondition(queue.flush() && sent.last == .init(id: "new-session", position: 2))
        succeeds = false
        queue.enqueue(id: "closed-pipe", position: 10)
        precondition(!queue.flush())
        let count = sent.count
        try await Task.sleep(for: .milliseconds(400))
        precondition(sent.count == count)
        succeeds = true
        queue.enqueue(id: "automatic", position: 20)
        let deadline = ContinuousClock.now + .seconds(3)
        while sent.count == count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        precondition(sent.last == .init(id: "automatic", position: 20))
        print("Seek bursts: final destination, flush, stop/replacement, failed send and cancelled deadlines: OK")
    }
}
