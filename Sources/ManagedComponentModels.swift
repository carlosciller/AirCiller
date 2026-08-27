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

    var formula: String {
        switch self {
        case .ffmpeg: "ffmpeg"
        case .airPlay: "python@3.13"
        }
    }

    var purpose: String {
        switch self {
        case .ffmpeg:
            "Analiza y prepara las películas, el audio y los subtítulos."
        case .airPlay:
            "Python 3.13 ejecuta el motor AirPlay 2 incluido con AirCiller."
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
