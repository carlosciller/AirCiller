struct PreparedCacheSettingsState: Equatable, Sendable {
    enum OperationFailure: Equatable, Sendable {
        case clear
        case trim
    }

    private(set) var sizeBytes: Int64?
    private(set) var sizeReadFailed = false
    private(set) var operationFailure: OperationFailure?

    mutating func receivedSize(_ bytes: Int64) {
        sizeBytes = bytes
        sizeReadFailed = false
    }

    mutating func failedToReadSize() {
        sizeBytes = nil
        sizeReadFailed = true
    }

    mutating func beginOperation() {
        operationFailure = nil
    }

    mutating func failedOperation(_ failure: OperationFailure) {
        operationFailure = failure
    }
}

enum CacheCleanupAvailability {
    static func canClear(reportedBytes: Int64?, previousFailure: Bool, busy: Bool) -> Bool {
        !busy && (reportedBytes != 0 || previousFailure)
    }
}
