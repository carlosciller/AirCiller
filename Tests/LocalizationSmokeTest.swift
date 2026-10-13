import Foundation

@main
struct LocalizationSmokeTest {
    static func main() throws {
        let projectDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resources = projectDirectory.appendingPathComponent("Resources", isDirectory: true)

        let english = try localizedBundle(language: "en", resources: resources)
        let spanish = try localizedBundle(language: "es", resources: resources)
        let englishTable = try stringsTable(language: "en", resources: resources)
        let spanishTable = try stringsTable(language: "es", resources: resources)

        try expect(
            Set(englishTable.keys) == Set(spanishTable.keys),
            "English and Spanish must expose the same localization keys."
        )
        try expect(
            spanishTable.allSatisfy { $0.key == $0.value },
            "Spanish source keys must remain explicit Spanish translations during the transition."
        )

        try expect(
            english.localizedString(
                forKey: "Abrir película…", value: "Abrir película…", table: "Localizable")
                == "Open Movie…",
            "The English interface translation is missing."
        )
        try expect(
            spanish.localizedString(
                forKey: "Abrir película…", value: "Abrir película…", table: "Localizable")
                == "Abrir película…",
            "The Spanish interface fallback changed unexpectedly."
        )
        try expect(
            english.localizedString(
                forKey: "CFBundleTypeName", value: "", table: "InfoPlist")
                == "AirCiller-compatible movie",
            "The English Info.plist translation is missing."
        )
        try expect(
            spanish.localizedString(
                forKey: "CFBundleTypeName", value: "", table: "InfoPlist")
                == "Película compatible con AirCiller",
            "The Spanish Info.plist translation is missing."
        )

        for (key, count, expectedEnglish, expectedSpanish) in [
            ("%lld episodio", 1, "1 episode", "1 episodio"),
            ("%lld episodios", 2, "2 episodes", "2 episodios"),
            ("%lld visto", 1, "1 watched", "1 visto"),
            ("%lld archivo añadido", 1, "1 file added", "1 archivo añadido"),
            ("%lld archivos añadidos", 0, "0 files added", "0 archivos añadidos"),
            ("%lld ubicación no disponible", 1, "1 location unavailable", "1 ubicación no disponible"),
        ] {
            try expect(
                String(format: english.localizedString(forKey: key, value: key, table: "Localizable"), Int64(count))
                    == expectedEnglish,
                "English library counter changed: \(key)")
            try expect(
                String(format: spanish.localizedString(forKey: key, value: key, table: "Localizable"), Int64(count))
                    == expectedSpanish,
                "Spanish library counter changed: \(key)")
        }

        let infoPlist = projectDirectory.appendingPathComponent("Info.plist")
        let data = try Data(contentsOf: infoPlist)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let dictionary = plist as? [String: Any] else {
            throw TestFailure("Info.plist is not a dictionary.")
        }
        try expect(
            dictionary["CFBundleDevelopmentRegion"] as? String == "en",
            "English must remain the development language."
        )
        try expect(
            Set(dictionary["CFBundleLocalizations"] as? [String] ?? []) == Set(["en", "es"]),
            "Info.plist must declare English and Spanish."
        )

        print("Localization smoke test: OK")
    }

    private static func localizedBundle(language: String, resources: URL) throws -> Bundle {
        let path = resources.appendingPathComponent("\(language).lproj", isDirectory: true).path
        guard let bundle = Bundle(path: path) else {
            throw TestFailure("Could not load \(language).lproj.")
        }
        return bundle
    }

    private static func stringsTable(language: String, resources: URL) throws -> [String: String] {
        let url =
            resources
            .appendingPathComponent("\(language).lproj", isDirectory: true)
            .appendingPathComponent("Localizable.strings")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let table = plist as? [String: String] else {
            throw TestFailure("Could not parse the \(language) localization table.")
        }
        return table
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw TestFailure(message) }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
