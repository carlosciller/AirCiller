import Foundation

enum AirCillerError: LocalizedError {
    case ffmpegMissing
    case ffprobeMissing
    case probeFailed(String)
    case noVideo
    case ffmpegStopped(String)
    case unsupportedSubtitle(String)
    case subtitlePreparationFailed(String)
    case invalidVODPackage(String)

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing: return "ffmpeg missing"
        case .ffprobeMissing: return "ffprobe missing"
        case .probeFailed(let text): return text
        case .noVideo: return "no video"
        case .ffmpegStopped(let text): return text
        case .unsupportedSubtitle(let text): return text
        case .subtitlePreparationFailed(let text): return text
        case .invalidVODPackage(let text): return text
        }
    }
}
