import Foundation
import Observation

enum ManagedComponent: String, CaseIterable, Identifiable, Sendable {
    case ffmpeg
    case airPlay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ffmpeg: "FFmpeg"
        case .airPlay: "AirPlay"
        }
    }

    var formula: String {
        switch self {
        case .ffmpeg: "ffmpeg"
        case .airPlay: "python@3.13"
        }
    }

    var purpose: String {
        switch self {
        case .ffmpeg:
            "Analiza y prepara las películas, el audio y los subtítulos."
        case .airPlay:
            "Python 3.13 ejecuta el motor AirPlay 2 incluido con AirCiller."
        }
    }
}

struct ManagedComponentStatus: Equatable, Sendable {
    let component: ManagedComponent
    let version: String?
    let path: String?
    let source: String?
    let isCompatible: Bool

    var isInstalled: Bool { path != nil }

    static func missing(_ component: ManagedComponent) -> Self {
        Self(
            component: component,
            version: nil,
            path: nil,
            source: nil,
            isCompatible: false
        )
    }
}

@Observable
@MainActor
final class ComponentManager {
    private(set) var statuses: [ManagedComponent: ManagedComponentStatus] = [:]
    private(set) var homebrewPath: String?
    private(set) var isRefreshing = false
    private(set) var activeComponent: ManagedComponent?
    private(set) var operationMessage: String?
    private(set) var operationOutput: String?

    @ObservationIgnored private var operationTask: Task<Void, Never>?

    func status(for component: ManagedComponent) -> ManagedComponentStatus {
        statuses[component] ?? .missing(component)
    }

    func refresh() async {
        guard activeComponent == nil else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let recordedPythonPath = Self.recordedPythonPath()
        let snapshot = await Task.detached(priority: .utility) {
            await Self.scan(recordedPythonPath: recordedPythonPath)
        }.value
        guard !Task.isCancelled else { return }
        statuses = snapshot.statuses
        homebrewPath = snapshot.homebrewPath
    }

    func installOrUpdate(_ component: ManagedComponent) {
        guard activeComponent == nil else { return }
        guard let homebrewPath else {
            operationMessage = L10n.text("Homebrew no está instalado.")
            return
        }

        activeComponent = component
        operationOutput = nil
        operationMessage = L10n.format("Preparando %@…", component.title)
        let formula = component.formula

        operationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let installed = await Self.isFormulaInstalled(
                    brewPath: homebrewPath,
                    formula: formula
                )
                try Task.checkCancellation()
                self.operationMessage = L10n.format(
                    installed ? "Actualizando %@ con Homebrew…" : "Instalando %@ con Homebrew…",
                    component.title
                )
                let result = try await Self.runHomebrew(
                    brewPath: homebrewPath,
                    arguments: [installed ? "upgrade" : "install", formula]
                )
                try Task.checkCancellation()
                guard result.status == 0 else {
                    throw ComponentManagerError.commandFailed(result.output)
                }
                self.operationOutput = Self.lastMeaningfulLine(in: result.output)
                self.operationMessage = L10n.format("%@ está listo.", component.title)
                self.activeComponent = nil
                self.operationTask = nil
                await self.refresh()
            } catch is CancellationError {
                self.operationMessage = L10n.text("Operación cancelada.")
                self.activeComponent = nil
                self.operationTask = nil
                await self.refresh()
            } catch {
                self.operationOutput = error.localizedDescription
                self.operationMessage = L10n.format("No se pudo preparar %@.", component.title)
                self.activeComponent = nil
                self.operationTask = nil
                await self.refresh()
            }
        }
    }

    func cancelOperation() {
        operationTask?.cancel()
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
        let brewPath = executablePath(in: [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
        ])

        let ffmpegPath = executablePath(in: [
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
            source: ffmpegPath.map(componentSource(for:)),
            isCompatible: ffmpegPath != nil && ffmpegVersion != nil
        )

        var pythonCandidates = [
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
        let pythonStatus = ManagedComponentStatus(
            component: .airPlay,
            version: pythonVersion,
            path: pythonPath,
            source: pythonPath.map(componentSource(for:)),
            isCompatible: isCompatiblePythonVersion(pythonVersion)
        )

        return ComponentSnapshot(
            statuses: [
                .ffmpeg: ffmpegStatus,
                .airPlay: pythonStatus,
            ],
            homebrewPath: brewPath
        )
    }

    private nonisolated static func recordedPythonPath() -> String? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let marker =
            resources
            .appendingPathComponent("VendorPython", isDirectory: true)
            .appendingPathComponent(".airciller-python-executable")
        return try? String(contentsOf: marker, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private nonisolated static func isFormulaInstalled(
        brewPath: String,
        formula: String
    ) async -> Bool {
        guard
            let result = try? await runProcess(
                executablePath: brewPath,
                arguments: ["list", "--versions", formula],
                environment: homebrewEnvironment,
                maximumOutputBytes: 262_144
            )
        else { return false }
        return result.status == 0 && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private nonisolated static func runHomebrew(
        brewPath: String,
        arguments: [String]
    ) async throws -> ProcessResult {
        try await runProcess(
            executablePath: brewPath,
            arguments: arguments,
            environment: homebrewEnvironment,
            maximumOutputBytes: 2_097_152
        )
    }

    private nonisolated static var homebrewEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        environment["HOMEBREW_NO_ENV_HINTS"] = "1"
        environment["NONINTERACTIVE"] = "1"
        return environment
    }

    private nonisolated static func runProcess(
        executablePath: String,
        arguments: [String],
        environment: [String: String]?,
        maximumOutputBytes: Int
    ) async throws -> ProcessResult {
        let process = Process()
        let output = Pipe()
        let buffer = ProcessDataBuffer(maximumBytes: maximumOutputBytes)
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
            } else {
                buffer.append(data)
            }
        }
        defer { output.fileHandleForReading.readabilityHandler = nil }

        let status = try await CancellableProcess(process).run()
        buffer.append(output.fileHandleForReading.readDataToEndOfFile())
        let text = String(decoding: buffer.snapshot, as: UTF8.self)
        return ProcessResult(status: status, output: text)
    }

    private nonisolated static func firstMatch(in text: String, pattern: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = expression.firstMatch(in: text, range: range), match.numberOfRanges > 1,
            let capture = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[capture])
    }

    private nonisolated static func lastMeaningfulLine(in output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last(where: { !$0.isEmpty })
    }
}

private struct ComponentSnapshot: Sendable {
    let statuses: [ManagedComponent: ManagedComponentStatus]
    let homebrewPath: String?
}

private struct ProcessResult: Sendable {
    let status: Int32
    let output: String
}

private enum ComponentManagerError: LocalizedError, Sendable {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let output):
            let message = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return message.isEmpty ? "Homebrew stopped before completing the operation." : message
        }
    }
}
