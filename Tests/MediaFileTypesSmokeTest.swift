import Foundation
import UniformTypeIdentifiers

@main
struct MediaFileTypesSmokeTest {
    static func main() throws {
        for ext in ["mkv", "mp4", "m4v", "mov", "ts", "mts", "m2ts"] {
            for spelling in [ext, ext.uppercased()] {
                try require(MediaFileTypes.accepts(URL(fileURLWithPath: "/tmp/Film.\(spelling)")))
            }
            let type = UTType(filenameExtension: ext, conformingTo: .movie)
            try require(type != nil && MediaFileTypes.contentTypes.contains(type!))
        }
        for name in ["film", "film.ts.txt", "film.avi", "film.m3u8", "film.iso"] {
            try require(!MediaFileTypes.accepts(URL(fileURLWithPath: "/tmp/\(name)")))
        }
        try require(!MediaFileTypes.accepts(URL(string: "https://example.invalid/live.ts")!))
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let plist = try Data(contentsOf: project.appendingPathComponent("Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any]
        let documents = info?["CFBundleDocumentTypes"] as? [[String: Any]]
        let registered = documents?.flatMap { $0["CFBundleTypeExtensions"] as? [String] ?? [] } ?? []
        try require(Set(registered) == Set(MediaFileTypes.extensions))
        print("Movie admission, Open panel types and Finder registration agree: OK")
    }

    private static func require(_ condition: Bool) throws {
        guard condition else { throw Failure.invalidAdmission }
    }

    private enum Failure: Error { case invalidAdmission }
}
