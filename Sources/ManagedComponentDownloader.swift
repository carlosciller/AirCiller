import Foundation

enum ManagedComponentDownloadStage: Sendable {
    case catalogue
    case downloading(Double)
    case verifying
    case installing
}

enum ManagedComponentDownloader {
    static func install(
        _ component: ManagedComponent,
        configuration: ManagedComponentConfiguration,
        progress: @escaping @Sendable (ManagedComponentDownloadStage) -> Void
    ) async throws {
        guard configuration.isReady,
            let manifestURL = configuration.manifestURL,
            let signatureURL = configuration.signatureURL,
            let publicKey = configuration.publicKey
        else {
            throw ManagedComponentDownloaderError.notConfigured
        }

        progress(.catalogue)
        async let manifestData = data(from: manifestURL, maximumBytes: 1_048_576)
        async let signatureData = data(from: signatureURL, maximumBytes: 16_384)
        let manifest = try ManagedComponentDistribution.verifiedManifest(
            data: await manifestData,
            signatureData: await signatureData,
            publicKeyBase64: publicKey
        )
        try Task.checkCancellation()
        let artifact = try ManagedComponentDistribution.artifact(for: component, in: manifest)

        let temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-Component-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }

        let archive = temporaryRoot.appendingPathComponent("component.zip")
        try await download(
            from: artifact.archiveURL,
            to: archive,
            maximumBytes: artifact.archiveSize,
            progress: { progress(.downloading($0)) }
        )
        try Task.checkCancellation()
        progress(.verifying)
        try ManagedComponentDistribution.validateArchive(archive, artifact: artifact)

        let extracted = temporaryRoot.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        progress(.installing)
        try await extract(archive: archive, to: extracted)
        try Task.checkCancellation()
        try await validateExecutable(in: extracted, artifact: artifact)
        try Task.checkCancellation()
        try ManagedComponentStore.install(extractedDirectory: extracted, artifact: artifact)
    }

    private static func data(from url: URL, maximumBytes: Int) async throws -> Data {
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response)
        guard data.count <= maximumBytes else {
            throw ManagedComponentDownloaderError.invalidResponse
        }
        return data
    }

    private static func download(
        from url: URL,
        to destination: URL,
        maximumBytes: Int64,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let limit = ManagedDownloadLimit(maximumBytes: maximumBytes)
        let delegate = ComponentDownloadProgressDelegate(limit: limit, progress: progress)
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
        let temporaryURL: URL
        let response: URLResponse
        do {
            (temporaryURL, response) = try await URLSession.shared.download(for: request, delegate: delegate)
        } catch {
            if limit.wasExceeded { throw ManagedComponentDownloaderError.invalidResponse }
            throw error
        }
        try validate(response: response)
        guard !limit.wasExceeded else { throw ManagedComponentDownloaderError.invalidResponse }
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
    }

    private static func validate(response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode),
            response.url?.scheme?.lowercased() == "https"
        else {
            throw ManagedComponentDownloaderError.invalidResponse
        }
    }

    private static func extract(archive: URL, to destination: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = [
            "-x", "-k", "--norsrc", "--noextattr", "--noqtn", "--noacl",
            archive.path, destination.path,
        ]
        process.standardOutput = FileHandle.nullDevice
        let errors = Pipe()
        let buffer = ProcessDataBuffer(maximumBytes: 64_000)
        errors.fileHandleForReading.readabilityHandler = { buffer.append($0.availableData) }
        process.standardError = errors
        let status = try await CancellableProcess(process).run {
            try? errors.fileHandleForWriting.close()
        }
        errors.fileHandleForReading.readabilityHandler = nil
        buffer.append(errors.fileHandleForReading.readDataToEndOfFile())
        guard status == 0 else {
            let message = String(decoding: buffer.snapshot, as: UTF8.self)
            throw ManagedComponentDownloaderError.extractionFailed(message)
        }
    }

    private static func validateExecutable(
        in extractedRoot: URL,
        artifact: ManagedComponentArtifact
    ) async throws {
        guard let executablePath = ManagedComponentDistribution.safeRelativePath(artifact.executablePath) else {
            throw ManagedComponentDownloaderError.invalidExecutable
        }
        let primaryExecutable = extractedRoot.appendingPathComponent(executablePath)
        let executableNames = artifact.component == .ffmpeg ? ["ffmpeg", "ffprobe"] : ["python3"]
        let expectedVersion = artifact.version.split(separator: "+", maxSplits: 1).first.map(String.init) ?? ""

        for executableName in executableNames {
            let executable = primaryExecutable.deletingLastPathComponent()
                .appendingPathComponent(executableName)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            let resolvedRoot = extractedRoot.resolvingSymlinksInPath().standardizedFileURL.path + "/"
            guard executable.path.hasPrefix(resolvedRoot),
                FileManager.default.isExecutableFile(atPath: executable.path)
            else {
                throw ManagedComponentDownloaderError.invalidExecutable
            }

            let process = Process()
            let output = Pipe()
            let buffer = ProcessDataBuffer(maximumBytes: 64_000)
            process.executableURL = executable
            process.arguments = artifact.component == .ffmpeg ? ["-version"] : ["--version"]
            process.standardOutput = output
            process.standardError = output
            output.fileHandleForReading.readabilityHandler = { buffer.append($0.availableData) }
            defer { output.fileHandleForReading.readabilityHandler = nil }
            let status = try await CancellableProcess(process).run {
                try? output.fileHandleForWriting.close()
            }
            buffer.append(output.fileHandleForReading.readDataToEndOfFile())
            let text = String(decoding: buffer.snapshot, as: UTF8.self)
            guard status == 0, !expectedVersion.isEmpty, text.contains(expectedVersion) else {
                throw ManagedComponentDownloaderError.invalidExecutable
            }
        }

        if artifact.component == .airPlay {
            guard let resources = Bundle.main.resourceURL else {
                throw ManagedComponentDownloaderError.invalidExecutable
            }
            let vendor = resources.appendingPathComponent("VendorPython", isDirectory: true)
            guard FileManager.default.fileExists(atPath: vendor.path) else {
                throw ManagedComponentDownloaderError.invalidExecutable
            }
            let result = try await CapturedProcess.run(
                executable: primaryExecutable,
                arguments: AirPlayRuntimeProbe.arguments,
                environment: AirPlayRuntimeProbe.environment(vendorDirectory: vendor),
                maximumOutputBytes: 64_000
            )
            let text = String(decoding: result.output + result.errorOutput, as: UTF8.self)
            guard AirPlayRuntimeProbe.isReady(status: result.status, output: text) else {
                throw ManagedComponentDownloaderError.invalidExecutable
            }
        }
    }
}

final class ManagedDownloadLimit: @unchecked Sendable {
    private let maximumBytes: Int64
    private let lock = NSLock()
    private var exceeded = false

    init(maximumBytes: Int64) {
        self.maximumBytes = max(0, maximumBytes)
    }

    var wasExceeded: Bool {
        lock.lock()
        defer { lock.unlock() }
        return exceeded
    }

    func shouldCancel(totalBytesWritten: Int64, totalBytesExpected: Int64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if totalBytesWritten > maximumBytes
            || (totalBytesExpected > 0 && totalBytesExpected > maximumBytes)
        {
            exceeded = true
        }
        return exceeded
    }
}

private final class ComponentDownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let limit: ManagedDownloadLimit
    private let progress: @Sendable (Double) -> Void

    init(limit: ManagedDownloadLimit, progress: @escaping @Sendable (Double) -> Void) {
        self.limit = limit
        self.progress = progress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        if limit.shouldCancel(
            totalBytesWritten: totalBytesWritten,
            totalBytesExpected: totalBytesExpectedToWrite
        ) {
            downloadTask.cancel()
            return
        }
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}
}

private enum ManagedComponentDownloaderError: LocalizedError, Sendable {
    case notConfigured
    case invalidResponse
    case extractionFailed(String)
    case invalidExecutable

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return L10n.text("Las descargas gestionadas no están configuradas en esta versión.")
        case .invalidResponse:
            return L10n.text("El servidor no devolvió una descarga válida.")
        case .extractionFailed(let detail):
            let cleaned = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return cleaned.isEmpty
                ? L10n.text("No se pudo abrir el componente descargado.")
                : L10n.format("No se pudo abrir el componente descargado: %@", cleaned)
        case .invalidExecutable:
            return L10n.text("El componente descargado no supera la comprobación de ejecución y versión.")
        }
    }
}
