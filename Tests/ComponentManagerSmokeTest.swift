import Foundation

@main
struct ComponentManagerSmokeTest {
    static func main() throws {
        guard
            ComponentManager.ffmpegVersion(
                from: "ffmpeg version 9.0.1 Copyright (c) the FFmpeg developers"
            ) == "9.0.1",
            ComponentManager.pythonVersion(from: "Python 3.13.7") == "3.13.7",
            ComponentManager.isCompatiblePythonVersion("3.13.7"),
            !ComponentManager.isCompatiblePythonVersion("3.14.0"),
            !ComponentManager.isCompatiblePythonVersion(nil)
        else {
            throw NSError(domain: "ComponentManagerSmokeTest.VersionParsing", code: 1)
        }

        let limit = ManagedDownloadLimit(maximumBytes: 100)
        guard !limit.shouldCancel(totalBytesWritten: 100, totalBytesExpected: 100),
            limit.shouldCancel(totalBytesWritten: 101, totalBytesExpected: 100),
            limit.wasExceeded
        else {
            throw NSError(domain: "ComponentManagerSmokeTest.DownloadLimit", code: 2)
        }

        print("Component version parsing, AirPlay readiness, and download limits: OK")
    }
}
