import Foundation

struct HTTPServerTelemetry: Sendable, Equatable {
    let totalBytesSent: Int64
    let activeTransfers: Int
    let completedTransfers: Int
    let expectedDisconnects: Int
    let unexpectedErrors: Int
    let activeBitsPerSecond: Double?
    let observedCapacityBitsPerSecond: Double?
    let lastActivity: Date?
    let hasConfirmedMediaRequest: Bool

    static let empty = HTTPServerTelemetry(
        totalBytesSent: 0,
        activeTransfers: 0,
        completedTransfers: 0,
        expectedDisconnects: 0,
        unexpectedErrors: 0,
        activeBitsPerSecond: nil,
        observedCapacityBitsPerSecond: nil,
        lastActivity: nil,
        hasConfirmedMediaRequest: false
    )
}
