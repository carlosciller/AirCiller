import Foundation
import Observation

@Observable
@MainActor
final class ComponentManager {
    private(set) var statuses: [ManagedComponent: ManagedComponentStatus] = [:]
    private(set) var hasRefreshed = false

    func status(for component: ManagedComponent) -> ManagedComponentStatus {
        statuses[component] ?? .missing(component)
    }

    func refresh() async {
        defer { hasRefreshed = true }

        let recordedPythonPath = Self.recordedPythonPath()
        let snapshot = await Self.scan(recordedPythonPath: recordedPythonPath)
        guard !Task.isCancelled else { return }
        statuses = snapshot.statuses
    }

    nonisolated static func ffmpegVersion(from output: String) -> String? {
        firstMatch(in: output, pattern: #"ffmpeg version\s+([^\s]+)"#)
    }

    nonisolated static func pythonVersion(from output: String) -> String? {
        firstMatch(in: output, pattern: #"Python\s+(\d+\.\d+\.\d+)"#)
    }

    nonisolated static func isCompatiblePythonVersion(_ version: String?) -> Bool {
        guard let version else { return false }
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count >= 2 && parts[0] == "3" && parts[1] == "13"
    }

    private nonisolated static func scan(recordedPythonPath: String?) async -> ComponentSnapshot {
        let bundledFFmpegPath = BundledEngine.ffmpegExecutable(named: "ffmpeg")?.path
        let ffmpegPath =
            BundledEngine.isRequired
            ? bundledFFmpegPath
            : bundledFFmpegPath
                ?? executablePath(in: [
                    "/opt/homebrew/bin/ffmpeg",
                    "/usr/local/bin/ffmpeg",
                    "/opt/local/bin/ffmpeg",
                ])
        let ffmpegOutput: String?
        if let ffmpegPath {
            ffmpegOutput = await commandOutput(executablePath: ffmpegPath, arguments: ["-version"])
        } else {
            ffmpegOutput = nil
        }
        let ffmpegVersion = ffmpegOutput.flatMap(ffmpegVersion(from:))
        let ffmpegStatus = ManagedComponentStatus(
            component: .ffmpeg,
            version: ffmpegVersion,
            path: ffmpegPath,
            source: ffmpegPath.map {
                bundledFFmpegPath == $0
                    ? "AirCiller"
                    : componentSource(for: $0)
            },
            isCompatible: ffmpegPath != nil && ffmpegVersion != nil
        )

        let bundledPythonPath = BundledEngine.airPlayPython()?.path
        var pythonCandidates =
            BundledEngine.isRequired
            ? [bundledPythonPath].compactMap { $0 }
            : [
                bundledPythonPath,
                recordedPythonPath,
                "/opt/homebrew/opt/python@3.13/bin/python3.13",
                "/opt/homebrew/bin/python3",
                "/usr/local/opt/python@3.13/bin/python3.13",
                "/usr/local/bin/python3.13",
                "/usr/local/bin/python3",
            ].compactMap { $0 }
        var seenPythonPaths = Set<String>()
        pythonCandidates = pythonCandidates.filter { seenPythonPaths.insert($0).inserted }
        let pythonPath = executablePath(in: pythonCandidates)
        let pythonOutput: String?
        if let pythonPath {
            pythonOutput = await commandOutput(executablePath: pythonPath, arguments: ["--version"])
        } else {
            pythonOutput = nil
        }
        let pythonVersion = pythonOutput.flatMap(pythonVersion(from:))
        let airPlayReady: Bool
        if isCompatiblePythonVersion(pythonVersion),
            let pythonPath,
            let vendor = bundledVendorDirectory(),
            let result = try? await runProcess(
                executablePath: pythonPath,
                arguments: AirPlayRuntimeProbe.arguments,
                environment: AirPlayRuntimeProbe.environment(vendorDirectory: vendor),
                maximumOutputBytes: 262_144
            )
        {
            airPlayReady = AirPlayRuntimeProbe.isReady(status: result.status, output: result.output)
        } else {
            airPlayReady = false
        }
        let pythonStatus = ManagedComponentStatus(
            component: .airPlay,
            version: pythonVersion,
            path: pythonPath,
            source: pythonPath.map {
                bundledPythonPath == $0
                    ? "AirCiller"
                    : componentSource(for: $0)
            },
            isCompatible: airPlayReady
        )

        return ComponentSnapshot(statuses: [.ffmpeg: ffmpegStatus, .airPlay: pythonStatus])
    }

    private nonisolated static func recordedPythonPath() -> String? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let marker =
            resources
            .appendingPathComponent("VendorPython", isDirectory: true)
            .appendingPathComponent(".airciller-python-executable")
        guard
            let value = try? String(contentsOf: marker, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        return BundledEngine.resolveRuntimeMarker(value, resources: resources)?.path
    }

    private nonisolated static func bundledVendorDirectory() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let vendor = resources.appendingPathComponent("VendorPython", isDirectory: true)
        return FileManager.default.fileExists(atPath: vendor.path) ? vendor : nil
    }

    private nonisolated static func executablePath(in candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private nonisolated static func componentSource(for path: String) -> String {
        if path.hasPrefix("/opt/homebrew/") || path.hasPrefix("/usr/local/") {
            return "Homebrew"
        }
        if path.hasPrefix("/opt/local/") {
            return "MacPorts"
        }
        return L10n.text("Sistema")
    }

    private nonisolated static func commandOutput(
        executablePath: String,
        arguments: [String]
    ) async -> String? {
        let result = try? await runProcess(
            executablePath: executablePath,
            arguments: arguments,
            environment: nil,
            maximumOutputBytes: 262_144
        )
        return result?.output
    }

    private nonisolated static func runProcess(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?,
        maximumOutputBytes: Int
    ) async throws -> ProcessResult {
        let result = try await CapturedProcess.run(
            executable: URL(fileURLWithPath: executablePath),
            arguments: arguments,
            environment: environment,
            maximumOutputBytes: maximumOutputBytes
        )
        return ProcessResult(
            status: result.status,
            output: String(decoding: result.output + result.errorOutput, as: UTF8.self)
        )
    }

    private nonisolated static func firstMatch(in text: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range), match.numberOfRanges > 1,
            let capture = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[capture])
    }

}

private struct ComponentSnapshot: Sendable {
    let statuses: [ManagedComponent: ManagedComponentStatus]
}

private struct ProcessResult: Sendable {
    let status: Int32
    let output: String
}
