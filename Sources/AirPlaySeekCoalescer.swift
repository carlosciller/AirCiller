import Foundation

/// Keep the final destination of a short scrub/skip burst. Intermediate seeks
/// can leave the receiver's active HLS subtitle cue missing after playback resumes.
@MainActor
final class AirPlaySeekCoalescer {
    struct Request: Equatable {
        let id: String
        let position: Double
    }

    private var pending: Request?
    private var task: Task<Void, Never>?
    private let send: (Request) -> Bool

    init(send: @escaping (Request) -> Bool) { self.send = send }

    func enqueue(id: String, position: Double) {
        cancel()
        pending = Request(id: id, position: position)
        task = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            self?.flush()
        }
    }

    @discardableResult
    func flush() -> Bool {
        task?.cancel()
        task = nil
        guard let request = pending else { return true }
        pending = nil
        return send(request)
    }

    func cancel() {
        task?.cancel()
        task = nil
        pending = nil
    }
}
