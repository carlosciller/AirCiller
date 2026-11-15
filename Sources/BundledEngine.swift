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
        if let bundled = executable(relativePath: relativePath, resources: resources, fileManager: fileManager) {
            return bundled
        }
        #if AIRCILLER_STANDALONE_TESTS
            // Explicit tool paths for standalone fixtures, never compiled into app builds.
            guard !isRequired, Bundle.main.bundleURL.pathExtension != "app",
                let path = ProcessInfo.processInfo.environment["AIRCILLER_TEST_\(name.uppercased())"],
                path.hasPrefix("/"), fileManager.isExecutableFile(atPath: path)
            else { return nil }
            return URL(fileURLWithPath: path)
        #else
            return nil
        #endif
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
