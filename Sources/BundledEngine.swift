import Foundation

/// Resolves the playback tools shipped as part of the AirCiller app release.
enum BundledEngine {
    static let ffmpegRelativePath = "Engine/ffmpeg/bin/ffmpeg"
    static let ffprobeRelativePath = "Engine/ffmpeg/bin/ffprobe"
    static let airPlayPythonRelativePath = "Engine/airplay/python/bin/python3"

    static var isRequired: Bool {
        isRequired(infoDictionary: Bundle.main.infoDictionary)
    }

    static func isRequired(infoDictionary: [String: Any]?) -> Bool {
        infoDictionary?["ACBundledEngineRequired"] as? Bool == true
    }

    static func ffmpegExecutable(
        named name: String,
        resources: URL? = Bundle.main.resourceURL,
        fileManager: FileManager = .default
    ) -> URL? {
        let relativePath: String
        switch name {
        case "ffmpeg": relativePath = ffmpegRelativePath
        case "ffprobe": relativePath = ffprobeRelativePath
        default: return nil
        }
        return executable(relativePath: relativePath, resources: resources, fileManager: fileManager)
    }

    static func airPlayPython(
        resources: URL? = Bundle.main.resourceURL,
        fileManager: FileManager = .default
    ) -> URL? {
        executable(
            relativePath: airPlayPythonRelativePath,
            resources: resources,
            fileManager: fileManager
        )
    }

    static func resolveRuntimeMarker(
        _ value: String,
        resources: URL? = Bundle.main.resourceURL
    ) -> URL? {
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("/") {
            return URL(fileURLWithPath: value)
        }
        return resources?.appendingPathComponent(value)
    }

    private static func executable(
        relativePath: String,
        resources: URL?,
        fileManager: FileManager
    ) -> URL? {
        guard let resources else { return nil }
        let url = resources.appendingPathComponent(relativePath)
        return fileManager.isExecutableFile(atPath: url.path) ? url : nil
    }
}
