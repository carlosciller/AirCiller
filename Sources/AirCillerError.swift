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
    case receiverDidNotRequestMedia

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing:
            return L10n.text("No se encuentra FFmpeg. Instálalo con Homebrew para usar AirCiller.")
        case .ffprobeMissing:
            return L10n.text("No se encuentra ffprobe. Se instala junto con FFmpeg.")
        case .probeFailed(let message):
            return L10n.format("No se pudo leer el archivo: %@", message)
        case .noVideo:
            return L10n.text("El archivo no contiene ninguna pista de vídeo.")
        case .ffmpegStopped(let message):
            return message.isEmpty
                ? L10n.text("El motor se detuvo antes de completar la película.")
                : L10n.format("El motor se detuvo: %@", message)
        case .unsupportedSubtitle(let message):
            return L10n.text(message)
        case .subtitlePreparationFailed(let message):
            return L10n.format("No se pudieron preparar los subtítulos: %@", L10n.text(message))
        case .invalidVODPackage(let message):
            return L10n.format(
                "La película preparada no superó la comprobación: %@",
                L10n.text(message)
            )
        case .receiverDidNotRequestMedia:
            return L10n.text(
                "El Apple TV aceptó la orden, pero no solicitó ningún dato de la película. AirCiller ha cerrado la sesión fantasma."
            )
        }
    }
}
