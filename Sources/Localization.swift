import Foundation

enum L10n {
    static var locale: Locale {
        Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
    }

    static func text(_ key: String) -> String {
        Bundle.main.localizedString(forKey: key, value: key, table: "Localizable")
    }

    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: locale, arguments: arguments)
    }

    static func helperText(_ message: String) -> String {
        let exact = text(message)
        guard exact == message, Bundle.main.preferredLocalizations.first != "es" else {
            return exact
        }

        let patterns: [(prefix: String, suffix: String, key: String)] = [
            (
                "El Apple TV exige autenticación o emparejamiento para este Mac. Detalle técnico: ",
                ".",
                "El Apple TV exige autenticación o emparejamiento para este Mac. Detalle técnico: %@."
            ),
            (
                "El Apple TV rechazó el stream de control AirPlay 2 (HTTP ",
                ").",
                "El Apple TV rechazó el stream de control AirPlay 2 (HTTP %@)."
            ),
            (
                "No se encontró ningún servicio AirPlay en ",
                ".",
                "No se encontró ningún servicio AirPlay en %@."
            ),
            (
                "Apple TV rechazó el cambio de reproducción (HTTP ",
                ")",
                "Apple TV rechazó el cambio de reproducción (HTTP %@)"
            ),
            (
                "Apple TV rechazó el salto (HTTP ",
                ")",
                "Apple TV rechazó el salto (HTTP %@)"
            ),
            (
                "Apple TV devolvió HTTP ",
                "",
                "Apple TV devolvió HTTP %@"
            ),
            (
                "Apple TV rechazó la orden AirPlay 2 (HTTP ",
                ")",
                "Apple TV rechazó la orden AirPlay 2 (HTTP %@)"
            ),
        ]

        for pattern in patterns where message.hasPrefix(pattern.prefix) && message.hasSuffix(pattern.suffix) {
            let start = message.index(message.startIndex, offsetBy: pattern.prefix.count)
            let end = message.index(message.endIndex, offsetBy: -pattern.suffix.count)
            guard start <= end else { continue }
            return format(pattern.key, String(message[start..<end]))
        }

        let credentialPrefix =
            "El Apple TV aceptó el código, pero rechazó la credencial nueva al verificarla: "
        if message.hasPrefix(credentialPrefix) {
            return format(
                "El Apple TV aceptó el código, pero rechazó la credencial nueva al verificarla: %@",
                String(message.dropFirst(credentialPrefix.count)))
        }
        return message
    }
}
