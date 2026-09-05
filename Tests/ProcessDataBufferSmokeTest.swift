import Foundation

@main
struct ProcessDataBufferSmokeTest {
    static func main() throws {
        for limit in [0, 1, 7, 64, 1_024] {
            let buffer = ProcessDataBuffer(maximumBytes: limit)
            var expected = Data()
            var saved: [(Data, Data)] = []
            for index in 0..<500 {
                let size = [0, 1, 3, 17, 128, 2_048][index % 6]
                // Exercise Data slices whose start index is not zero.
                let bytes = Data((0..<(size + 5)).map { UInt8(truncatingIfNeeded: $0 + index) }).dropFirst(
                    5)
                buffer.append(bytes)
                expected.append(bytes)
                expected = Data(expected.suffix(limit))
                let snapshot = buffer.snapshot
                guard snapshot == expected else {
                    throw failure("Tail mismatch at limit \(limit), write \(index)")
                }
                if index % 37 == 0 { saved.append((snapshot, expected)) }
            }
            guard saved.allSatisfy({ $0.0 == $0.1 }) else { throw failure("A saved snapshot changed") }
        }

        // Cross many compaction boundaries using writes smaller than the limit.
        let tail = ProcessDataBuffer(maximumBytes: 127)
        var reference = Data()
        for index in 0..<5_000 {
            let chunk = Data(repeating: UInt8(truncatingIfNeeded: index), count: index % 23 + 1)
            tail.append(chunk)
            reference.append(chunk)
            guard tail.snapshot == reference.suffix(127) else {
                throw failure("Compaction changed output")
            }
        }

        let unlimited = ProcessDataBuffer()
        DispatchQueue.concurrentPerform(iterations: 1_000) { _ in
            unlimited.append(Data(repeating: 42, count: 32))
            _ = unlimited.snapshot
        }
        guard unlimited.snapshot == Data(repeating: 42, count: 32_000) else {
            throw failure("Concurrent writes lost bytes")
        }
        let bounded = ProcessDataBuffer(maximumBytes: 513)
        DispatchQueue.concurrentPerform(iterations: 1_000) { _ in
            bounded.append(Data(repeating: 23, count: 17))
            precondition(bounded.snapshot.count <= 513)
        }
        guard bounded.snapshot == Data(repeating: 23, count: 513) else {
            throw failure("Concurrent bounded output changed")
        }
        print("Process buffer tails, compaction, snapshots and concurrent writes: OK")
    }

    static func failure(_ message: String) -> NSError {
        NSError(
            domain: "ProcessDataBufferSmokeTest", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
