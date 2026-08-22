import Foundation

final class ProcessDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumBytes: Int?
    private var data = Data()

    init(maximumBytes: Int? = nil) {
        self.maximumBytes = maximumBytes
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        data.append(newData)
        if let maximumBytes, data.count > maximumBytes {
            data = Data(data.suffix(maximumBytes))
        }
        lock.unlock()
    }

    var snapshot: Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
