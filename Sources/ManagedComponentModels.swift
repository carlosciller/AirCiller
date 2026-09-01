import Foundation

enum ManagedComponent: String, CaseIterable, Codable, Identifiable, Sendable {
    case ffmpeg
    case airPlay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ffmpeg: "FFmpeg"
        case .airPlay: "AirPlay"
        }
    }

}

struct ManagedComponentStatus: Equatable, Sendable {
    let component: ManagedComponent
    let version: String?
    let path: String?
    let source: String?
    let isCompatible: Bool

    var isInstalled: Bool { path != nil }

    static func missing(_ component: ManagedComponent) -> Self {
        Self(
            component: component,
            version: nil,
            path: nil,
            source: nil,
            isCompatible: false
        )
    }
}
