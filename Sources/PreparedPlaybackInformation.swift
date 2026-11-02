import Foundation

/// Immutable record of a completed local preparation, not receiver/HDMI metadata.
struct PreparedPlaybackInformation: Equatable {
    enum Route: String {
        case directMP4 = "MP4"
        case hls = "HLS/fMP4 VOD"
    }

    let route: Route
    let audio: String
    let subtitles: String

    init(route: Route, audio: AudioTrack?, outputMode: AudioOutputMode, subtitle: SubtitleTrack?) {
        self.route = route
        if let audio {
            self.audio =
                switch outputMode {
                case .original: L10n.format("%@, sin recodificar", audio.technicalDescription)
                case .compatible: L10n.text("Convertido a E-AC-3 con pérdida (hasta 5.1)")
                case .stereo: L10n.text("Convertido a AAC estéreo con pérdida")
                case .losslessFLAC: L10n.text("Convertido a FLAC sin pérdida; no conserva objetos Atmos")
                }
        } else {
            self.audio = L10n.text("Sin audio")
        }
        subtitles =
            subtitle == nil
            ? L10n.text("Desactivados")
            : L10n.text(route == .directMP4 ? "Texto seleccionable en MP4" : "WebVTT seleccionable")
    }
}
