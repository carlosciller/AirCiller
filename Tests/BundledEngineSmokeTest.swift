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
            !BundledEngine.isRequired(infoDictionary: [:])
        else {
            throw NSError(domain: "BundledEngineSmokeTest", code: 1)
        }

        // Explicit test paths cannot override an available bundled executable.
        guard
            BundledEngine.ffmpegExecutable(named: "ffmpeg", resources: root)?.path
                == root.appendingPathComponent(BundledEngine.ffmpegRelativePath).path
        else { throw NSError(domain: "BundledEngineSmokeTest.Precedence", code: 2) }

        for relativePath in [
            BundledEngine.ffmpegRelativePath, BundledEngine.ffprobeRelativePath,
            BundledEngine.airPlayPythonRelativePath,
        ] {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644], ofItemAtPath: root.appendingPathComponent(relativePath).path
            )
        }
        guard BundledEngine.airPlayPython(resources: root) == nil,
            BundledEngine.airPlayPython(resources: nil) == nil
        else { throw NSError(domain: "BundledEngineSmokeTest.Python", code: 3) }

        for name in ["ffmpeg", "ffprobe"] {
            #if AIRCILLER_STANDALONE_TESTS
                let path = ProcessInfo.processInfo.environment["AIRCILLER_TEST_\(name.uppercased())"]
                let expected = path.flatMap {
                    $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0)
                        ? URL(fileURLWithPath: $0) : nil
                }
            #else
                let expected: URL? = nil
            #endif
            guard BundledEngine.ffmpegExecutable(named: name, resources: root) == expected,
                BundledEngine.ffmpegExecutable(named: name, resources: nil) == expected
            else { throw NSError(domain: "BundledEngineSmokeTest.Unavailable", code: 4) }
        }
        try FileManager.default.removeItem(at: root)
        guard BundledEngine.airPlayPython(resources: root) == nil else {
            throw NSError(domain: "BundledEngineSmokeTest.Missing", code: 5)
        }
        print("Bundled engine precedence, unavailable tools and test-only explicit paths: OK")
    }
}
