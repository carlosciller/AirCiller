import AppKit

@main
@MainActor
struct SubtitleOCRCancellationSmokeTest {
    static func main() async throws {
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) { _exit(2) }
        let image = NSImage(size: NSSize(width: 1280, height: 360))
        image.lockFocus()
        NSColor.black.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        NSString(string: "AIRCILLER LOCAL SUBTITLE").draw(
            at: NSPoint(x: 40, y: 140),
            withAttributes: [
                .font: NSFont.systemFont(ofSize: 64, weight: .bold), .foregroundColor: NSColor.white,
            ])
        image.unlockFocus()
        guard let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw Failure.image }
        let progress = AsyncStream<Int>.makeStream()
        var completed = 0
        let task = Task {
            for index in 0..<100 {
                let result = try await SubtitleOCRService.recognize(in: bitmap, preferredLanguages: ["en-US"])
                guard result.text.uppercased().contains("AIRCILLER") else { throw Failure.recognition }
                completed += 1
                progress.continuation.yield(index)
            }
        }
        var iterator = progress.stream.makeAsyncIterator()
        guard await iterator.next() != nil, completed > 0, completed < 100 else { throw Failure.notStarted }
        let countAtStop = completed
        let began = ContinuousClock.now
        task.cancel()
        do {
            try await task.value
            throw Failure.notCancelled
        } catch is CancellationError {}
        progress.continuation.finish()
        guard completed == countAtStop, began.duration(to: .now) < .seconds(3) else { throw Failure.lateResult }
        let alreadyCancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SubtitleOCRService.recognize(in: bitmap)
        }
        do {
            _ = try await alreadyCancelled.value
            throw Failure.notCancelled
        } catch is CancellationError {}
        print(
            "Local Vision batch cancellation: real text recognized, no later result, pre-cancelled requests rejected: OK"
        )
    }
    private enum Failure: Error { case image, recognition, notStarted, notCancelled, lateResult }
}
