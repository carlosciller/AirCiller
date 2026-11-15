import Foundation

@main
struct ComponentManagerSmokeTest {
    @MainActor
    static func main() async throws {
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

        // This standalone test has no bundled engines. Installed host tools
        // must not turn missing app components into compatible ones.
        let manager = ComponentManager()
        await manager.refresh()
        guard manager.hasRefreshed,
            manager.status(for: .ffmpeg).path == nil,
            !manager.status(for: .ffmpeg).isCompatible,
            manager.status(for: .airPlay).path == nil,
            !manager.status(for: .airPlay).isCompatible
        else { throw NSError(domain: "ComponentManagerSmokeTest.HostFallback", code: 2) }
        print("Bundled component versions and no host-engine fallback: OK")
    }
}
