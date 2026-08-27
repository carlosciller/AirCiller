import CryptoKit
import Foundation

struct ManagedComponentConfiguration: Equatable, Sendable {
    let manifestURL: URL?
    let signatureURL: URL?
    let publicKey: String?

    var isReady: Bool {
        manifestURL?.scheme?.lowercased() == "https"
            && signatureURL?.scheme?.lowercased() == "https"
            && publicKey.flatMap { Data(base64Encoded: $0) }?.count == 32
    }

    static func load(from infoDictionary: [String: Any]?) -> Self {
        Self(
            manifestURL: normalizedString(infoDictionary?["ACComponentManifestURL"])
                .flatMap(URL.init(string:)),
            signatureURL: normalizedString(infoDictionary?["ACComponentManifestSignatureURL"])
                .flatMap(URL.init(string:)),
            publicKey: normalizedString(infoDictionary?["ACComponentPublicEDKey"])
        )
    }

    private static func normalizedString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }
}

struct ManagedComponentManifest: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let artifacts: [ManagedComponentArtifact]
}

struct ManagedComponentArtifact: Codable, Equatable, Sendable {
    let component: ManagedComponent
    let version: String
    let architecture: String
    let minimumSystemVersion: String
    let archiveURL: URL
    let archiveSize: Int64
    let sha256: String
    let executablePath: String
}

struct ManagedComponentInstallation: Codable, Equatable, Sendable {
    let version: String
    let executablePath: String
    let previousVersion: String?
}

enum ManagedComponentDistribution {
    static let schemaVersion = 1

    static func verifiedManifest(
        data: Data,
        signatureData: Data,
        publicKeyBase64: String
    ) throws -> ManagedComponentManifest {
        guard let publicKeyData = Data(base64Encoded: publicKeyBase64),
            let signature = decodedSignature(signatureData)
        else {
            throw ManagedComponentDistributionError.invalidSignature
        }
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        guard publicKey.isValidSignature(signature, for: data) else {
            throw ManagedComponentDistributionError.invalidSignature
        }
        let manifest = try JSONDecoder().decode(ManagedComponentManifest.self, from: data)
        guard manifest.schemaVersion == schemaVersion else {
            throw ManagedComponentDistributionError.unsupportedManifest
        }
        return manifest
    }

    static func artifact(
        for component: ManagedComponent,
        in manifest: ManagedComponentManifest,
        architecture: String = currentArchitecture,
        systemVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion
    ) throws -> ManagedComponentArtifact {
        guard
            let artifact = manifest.artifacts.first(where: {
                $0.component == component
                    && $0.architecture == architecture
                    && isSystemVersion(systemVersion, atLeast: $0.minimumSystemVersion)
                    && $0.archiveURL.scheme?.lowercased() == "https"
                    && $0.archiveURL.user == nil
                    && $0.archiveURL.password == nil
                    && $0.archiveSize > 0
                    && $0.sha256.count == 64
                    && $0.sha256.allSatisfy(\.isHexDigit)
                    && isSafeVersion($0.version)
                    && safeRelativePath($0.executablePath) != nil
            })
        else {
            throw ManagedComponentDistributionError.noCompatibleArtifact
        }
        return artifact
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            guard !data.isEmpty else { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func validateArchive(_ url: URL, artifact: ManagedComponentArtifact) throws {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard Int64(values.fileSize ?? -1) == artifact.archiveSize else {
            throw ManagedComponentDistributionError.invalidArchiveSize
        }
        guard try sha256(of: url).caseInsensitiveCompare(artifact.sha256) == .orderedSame else {
            throw ManagedComponentDistributionError.invalidArchiveHash
        }
    }

    static func currentArchitectureName() -> String { currentArchitecture }

    private static func decodedSignature(_ data: Data) -> Data? {
        if data.count == 64 { return data }
        guard
            let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        return Data(base64Encoded: value)
    }

    private static func isSystemVersion(
        _ version: OperatingSystemVersion,
        atLeast minimum: String
    ) -> Bool {
        let parts = minimum.split(separator: ".").compactMap { Int($0) }
        guard !parts.isEmpty else { return false }
        let required = OperatingSystemVersion(
            majorVersion: parts[0],
            minorVersion: parts.count > 1 ? parts[1] : 0,
            patchVersion: parts.count > 2 ? parts[2] : 0
        )
        if version.majorVersion != required.majorVersion {
            return version.majorVersion > required.majorVersion
        }
        if version.minorVersion != required.minorVersion {
            return version.minorVersion > required.minorVersion
        }
        return version.patchVersion >= required.patchVersion
    }

    static func safeRelativePath(_ path: String) -> String? {
        guard !path.isEmpty, path.count <= 1_024, !path.hasPrefix("/"), !path.contains("\\") else {
            return nil
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard
            components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0 != "~" })
        else { return nil }
        return path
    }

    static func isSafeVersion(_ version: String) -> Bool {
        guard !version.isEmpty, version.count <= 128 else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-")
        return version.unicodeScalars.allSatisfy(allowed.contains)
            && version != "."
            && version != ".."
    }

    private static var currentArchitecture: String {
        #if arch(arm64)
            return "arm64"
        #elseif arch(x86_64)
            return "x86_64"
        #else
            return "unknown"
        #endif
    }
}

enum ManagedComponentStore {
    static func activeInstallation(
        for component: ManagedComponent,
        root: URL = applicationSupportRoot
    ) -> ManagedComponentInstallation? {
        let recordURL = componentRoot(component, root: root).appendingPathComponent("current.json")
        guard let data = try? Data(contentsOf: recordURL) else { return nil }
        return try? JSONDecoder().decode(ManagedComponentInstallation.self, from: data)
    }

    static func executableURL(
        for component: ManagedComponent,
        named executableName: String? = nil,
        root: URL = applicationSupportRoot
    ) -> URL? {
        guard let installation = activeInstallation(for: component, root: root),
            ManagedComponentDistribution.isSafeVersion(installation.version),
            let storedExecutablePath = ManagedComponentDistribution.safeRelativePath(
                installation.executablePath
            )
        else { return nil }
        let componentRoot = componentRoot(component, root: root)
        let versionsRoot = componentRoot.appendingPathComponent("versions", isDirectory: true)
        let versionRoot =
            versionsRoot
            .appendingPathComponent(installation.version, isDirectory: true)
        let resolvedVersionsRoot = versionsRoot.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let resolvedVersionRoot = versionRoot.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedVersionRoot.path.hasPrefix(resolvedVersionsRoot) else { return nil }

        var executable = resolvedVersionRoot.appendingPathComponent(storedExecutablePath)
        if let executableName {
            guard executableName == URL(fileURLWithPath: executableName).lastPathComponent,
                !executableName.contains("/")
            else { return nil }
            executable.deleteLastPathComponent()
            executable.appendPathComponent(executableName)
        }
        let resolvedRoot = resolvedVersionRoot.path + "/"
        let resolvedExecutable = executable.resolvingSymlinksInPath().standardizedFileURL
        guard resolvedExecutable.path.hasPrefix(resolvedRoot),
            FileManager.default.isExecutableFile(atPath: resolvedExecutable.path)
        else { return nil }
        return resolvedExecutable
    }

    static func install(
        extractedDirectory: URL,
        artifact: ManagedComponentArtifact,
        root: URL = applicationSupportRoot
    ) throws {
        guard ManagedComponentDistribution.isSafeVersion(artifact.version),
            ManagedComponentDistribution.safeRelativePath(artifact.executablePath) != nil
        else {
            throw ManagedComponentDistributionError.invalidArchiveContents
        }
        let manager = FileManager.default
        let componentRoot = componentRoot(artifact.component, root: root)
        let versionsRoot = componentRoot.appendingPathComponent("versions", isDirectory: true)
        try manager.createDirectory(at: versionsRoot, withIntermediateDirectories: true)

        let destination = versionsRoot.appendingPathComponent(artifact.version, isDirectory: true)
        let staging = versionsRoot.appendingPathComponent(".install-\(UUID().uuidString)", isDirectory: true)
        try manager.copyItem(at: extractedDirectory, to: staging)
        do {
            try validateInstalledTree(staging, executablePath: artifact.executablePath)
            if manager.fileExists(atPath: destination.path) {
                try validateInstalledTree(destination, executablePath: artifact.executablePath)
                try manager.removeItem(at: staging)
            } else {
                try manager.moveItem(at: staging, to: destination)
            }

            let previous = activeInstallation(for: artifact.component, root: root)?.version
            let installation = ManagedComponentInstallation(
                version: artifact.version,
                executablePath: artifact.executablePath,
                previousVersion: previous == artifact.version ? nil : previous
            )
            try writeInstallation(installation, component: artifact.component, root: root)
            pruneVersions(
                for: artifact.component,
                keeping: Set([installation.version, installation.previousVersion].compactMap { $0 }),
                root: root
            )
        } catch {
            try? manager.removeItem(at: staging)
            throw error
        }
    }

    static func rollback(
        _ component: ManagedComponent,
        root: URL = applicationSupportRoot
    ) throws {
        guard let current = activeInstallation(for: component, root: root),
            let previousVersion = current.previousVersion,
            ManagedComponentDistribution.isSafeVersion(previousVersion)
        else {
            throw ManagedComponentDistributionError.rollbackUnavailable
        }
        let previousRoot = componentRoot(component, root: root)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(previousVersion, isDirectory: true)
        guard FileManager.default.fileExists(atPath: previousRoot.path) else {
            throw ManagedComponentDistributionError.rollbackUnavailable
        }
        let previousExecutablePath = try executablePath(in: previousRoot)
        let record = ManagedComponentInstallation(
            version: previousVersion,
            executablePath: previousExecutablePath,
            previousVersion: current.version
        )
        try writeInstallation(record, component: component, root: root)
    }

    static func hasRollback(
        for component: ManagedComponent,
        root: URL = applicationSupportRoot
    ) -> Bool {
        guard let previous = activeInstallation(for: component, root: root)?.previousVersion,
            ManagedComponentDistribution.isSafeVersion(previous)
        else { return false }
        let previousRoot = componentRoot(component, root: root)
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(previous, isDirectory: true)
        return (try? executablePath(in: previousRoot)) != nil
    }

    private static var applicationSupportRoot: URL {
        let base =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("AirCiller/Components", isDirectory: true)
    }

    private static func componentRoot(_ component: ManagedComponent, root: URL) -> URL {
        root.appendingPathComponent(component.rawValue, isDirectory: true)
    }

    private static func validateInstalledTree(_ root: URL, executablePath: String) throws {
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isSymbolicLinkKey],
                options: []
            )
        else {
            throw ManagedComponentDistributionError.invalidArchiveContents
        }
        for case let fileURL as URL in enumerator {
            guard fileURL.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(rootPath) else {
                throw ManagedComponentDistributionError.invalidArchiveContents
            }
        }
        let executable = root.appendingPathComponent(executablePath)
        guard executable.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(rootPath),
            FileManager.default.isExecutableFile(atPath: executable.path)
        else {
            throw ManagedComponentDistributionError.missingExecutable
        }
    }

    private static func pruneVersions(
        for component: ManagedComponent,
        keeping retainedVersions: Set<String>,
        root: URL
    ) {
        let versionsRoot = componentRoot(component, root: root)
            .appendingPathComponent("versions", isDirectory: true)
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: versionsRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        else { return }
        for entry in entries where !retainedVersions.contains(entry.lastPathComponent) {
            guard
                (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                ManagedComponentDistribution.isSafeVersion(entry.lastPathComponent)
            else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private static func executablePath(in versionRoot: URL) throws -> String {
        let metadata = versionRoot.appendingPathComponent("airciller-component.json")
        guard let data = try? Data(contentsOf: metadata),
            let value = try? JSONDecoder().decode(ComponentMetadata.self, from: data),
            ManagedComponentDistribution.safeRelativePath(value.executablePath) != nil
        else {
            throw ManagedComponentDistributionError.rollbackUnavailable
        }
        return value.executablePath
    }

    private static func writeInstallation(
        _ installation: ManagedComponentInstallation,
        component: ManagedComponent,
        root: URL
    ) throws {
        let componentRoot = componentRoot(component, root: root)
        try FileManager.default.createDirectory(at: componentRoot, withIntermediateDirectories: true)
        let versionRoot =
            componentRoot
            .appendingPathComponent("versions", isDirectory: true)
            .appendingPathComponent(installation.version, isDirectory: true)
        let metadata = try JSONEncoder().encode(ComponentMetadata(executablePath: installation.executablePath))
        try metadata.write(to: versionRoot.appendingPathComponent("airciller-component.json"), options: .atomic)

        let data = try JSONEncoder().encode(installation)
        try data.write(to: componentRoot.appendingPathComponent("current.json"), options: .atomic)
    }
}

private struct ComponentMetadata: Codable {
    let executablePath: String
}

enum ManagedComponentDistributionError: LocalizedError, Sendable {
    case invalidSignature
    case unsupportedManifest
    case noCompatibleArtifact
    case invalidArchiveSize
    case invalidArchiveHash
    case invalidArchiveContents
    case missingExecutable
    case rollbackUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidSignature:
            return L10n.text("La firma del catálogo de componentes no es válida.")
        case .unsupportedManifest:
            return L10n.text("El catálogo de componentes usa un formato incompatible.")
        case .noCompatibleArtifact:
            return L10n.text("No hay una descarga compatible con este Mac.")
        case .invalidArchiveSize:
            return L10n.text("La descarga no tiene el tamaño firmado esperado.")
        case .invalidArchiveHash:
            return L10n.text("La descarga no coincide con su huella SHA-256 firmada.")
        case .invalidArchiveContents:
            return L10n.text("La descarga contiene rutas que salen de su carpeta segura.")
        case .missingExecutable:
            return L10n.text("La descarga no contiene el ejecutable indicado por el catálogo.")
        case .rollbackUnavailable:
            return L10n.text("No hay una versión anterior disponible.")
        }
    }
}
