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

        let snapshot = await Self.scan()
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

    private nonisolated static func scan() async -> ComponentSnapshot {
        let ffmpegPath = BundledEngine.ffmpegExecutable(named: "ffmpeg")?.path
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
            source: ffmpegPath.map { _ in "AirCiller" },
            isCompatible: ffmpegPath != nil && ffmpegVersion != nil
        )

        let pythonPath = BundledEngine.airPlayPython()?.path
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
            source: pythonPath.map { _ in "AirCiller" },
            isCompatible: airPlayReady
        )

        return ComponentSnapshot(statuses: [.ffmpeg: ffmpegStatus, .airPlay: pythonStatus])
    }

    private nonisolated static func bundledVendorDirectory() -> URL? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let vendor = resources.appendingPathComponent("VendorPython", isDirectory: true)
        return FileManager.default.fileExists(atPath: vendor.path) ? vendor : nil
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
