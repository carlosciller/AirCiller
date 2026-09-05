import Foundation

final class ProcessDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int?
    private var data = Data()

    init(maximumBytes: Int? = nil) {
        precondition(maximumBytes == nil || maximumBytes! >= 0)
        self.maximumBytes = maximumBytes
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        if let maximumBytes {
            if newData.count >= maximumBytes {
                data = Data(newData.suffix(maximumBytes))
                return
            }
            // Amortize compaction across small writes. Retain at most twice
            // the limit internally; snapshots expose only the requested tail.
            if data.count > maximumBytes,
                data.count - maximumBytes >= maximumBytes - newData.count
            {
                data = Data(data.suffix(maximumBytes - newData.count))
            }
        }
        data.append(newData)
    }

    var snapshot: Data {
        lock.lock()
        defer { lock.unlock() }
        if let maximumBytes, data.count > maximumBytes {
            return Data(data.suffix(maximumBytes))
        }
        return data
    }
}
