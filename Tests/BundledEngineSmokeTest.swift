import Foundation

@main
struct BundledEngineSmokeTest {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-BundledEngine-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        for relativePath in [
            BundledEngine.ffmpegRelativePath,
            BundledEngine.ffprobeRelativePath,
            BundledEngine.airPlayPythonRelativePath,
        ] {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            _ = FileManager.default.createFile(atPath: url.path, contents: Data())
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: url.path
            )
        }

        guard BundledEngine.ffmpegExecutable(named: "ffmpeg", resources: root) != nil,
            BundledEngine.ffmpegExecutable(named: "ffprobe", resources: root) != nil,
            BundledEngine.ffmpegExecutable(named: "anything", resources: root) == nil,
            BundledEngine.airPlayPython(resources: root) != nil,
            BundledEngine.isRequired(infoDictionary: ["ACBundledEngineRequired": true]),
            !BundledEngine.isRequired(infoDictionary: [:]),
            BundledEngine.resolveRuntimeMarker(
                BundledEngine.airPlayPythonRelativePath,
                resources: root
            )?.path == root.appendingPathComponent(BundledEngine.airPlayPythonRelativePath).path
        else {
            throw NSError(domain: "BundledEngineSmokeTest", code: 1)
        }

        print("Bundled playback engine paths remain internal and executable: OK")
    }
}
