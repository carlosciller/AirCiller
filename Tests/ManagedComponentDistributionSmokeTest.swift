import CryptoKit
import Foundation

@main
struct ManagedComponentDistributionSmokeTest {
    static func main() throws {
        try verifyRepositoryManifest()

        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKey = privateKey.publicKey.rawRepresentation.base64EncodedString()
        let artifact = ManagedComponentArtifact(
            component: .ffmpeg,
            version: "9.0.1",
            architecture: ManagedComponentDistribution.currentArchitectureName(),
            minimumSystemVersion: "14.0",
            archiveURL: URL(string: "https://github.com/example/ffmpeg.zip")!,
            archiveSize: 128,
            sha256: String(repeating: "a", count: 64),
            executablePath: "bin/ffmpeg"
        )
        let manifest = ManagedComponentManifest(
            schemaVersion: ManagedComponentDistribution.schemaVersion,
            artifacts: [artifact]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(manifest)
        let signature = try privateKey.signature(for: data).base64EncodedString().data(using: .utf8)!
        let verified = try ManagedComponentDistribution.verifiedManifest(
            data: data,
            signatureData: signature,
            publicKeyBase64: publicKey
        )
        guard try ManagedComponentDistribution.artifact(for: .ffmpeg, in: verified) == artifact else {
            throw NSError(domain: "ManagedComponentDistributionSmokeTest.Manifest", code: 1)
        }

        let unsafeArtifact = ManagedComponentArtifact(
            component: .ffmpeg,
            version: "../outside",
            architecture: ManagedComponentDistribution.currentArchitectureName(),
            minimumSystemVersion: "14.0",
            archiveURL: URL(string: "https://github.com/example/ffmpeg.zip")!,
            archiveSize: 128,
            sha256: String(repeating: "z", count: 64),
            executablePath: "../bin/ffmpeg"
        )
        do {
            _ = try ManagedComponentDistribution.artifact(
                for: .ffmpeg,
                in: ManagedComponentManifest(schemaVersion: 1, artifacts: [unsafeArtifact])
            )
            throw NSError(domain: "ManagedComponentDistributionSmokeTest.Paths", code: 5)
        } catch ManagedComponentDistributionError.noCompatibleArtifact {
            // Expected.
        }

        var tampered = data
        tampered.append(0)
        do {
            _ = try ManagedComponentDistribution.verifiedManifest(
                data: tampered,
                signatureData: signature,
                publicKeyBase64: publicKey
            )
            throw NSError(domain: "ManagedComponentDistributionSmokeTest.Tampering", code: 2)
        } catch ManagedComponentDistributionError.invalidSignature {
            // Expected.
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-Component-Test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try installFixture(version: "9.0.1", root: root)
        try installFixture(version: "9.0.2", root: root)
        try installFixture(version: "9.0.3", root: root)
        let versionsRoot = root.appendingPathComponent("ffmpeg/versions", isDirectory: true)
        guard ManagedComponentStore.activeInstallation(for: .ffmpeg, root: root)?.version == "9.0.3",
            !FileManager.default.fileExists(atPath: versionsRoot.appendingPathComponent("9.0.1").path),
            ManagedComponentStore.hasRollback(for: .ffmpeg, root: root)
        else {
            throw NSError(domain: "ManagedComponentDistributionSmokeTest.Install", code: 3)
        }
        try ManagedComponentStore.rollback(.ffmpeg, root: root)
        guard ManagedComponentStore.activeInstallation(for: .ffmpeg, root: root)?.version == "9.0.2",
            ManagedComponentStore.executableURL(for: .ffmpeg, root: root) != nil
        else {
            throw NSError(domain: "ManagedComponentDistributionSmokeTest.Rollback", code: 4)
        }

        try verifyTamperedActivationRecordIsIgnored(root: root)
        try verifySameVersionRepair(root: root.appendingPathComponent("repair", isDirectory: true))

        print("Published signature, safe paths, repair, atomic activation, tamper rejection, and rollback: OK")
    }

    private static func verifyRepositoryManifest() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestData = try Data(
            contentsOf: projectRoot.appendingPathComponent("Distribution/components-v1.json")
        )
        let signatureData = try Data(
            contentsOf: projectRoot.appendingPathComponent("Distribution/components-v1.json.sig")
        )
        let infoData = try Data(contentsOf: projectRoot.appendingPathComponent("Info.plist"))
        let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any]
        guard let publicKey = info?["SUPublicEDKey"] as? String else {
            throw NSError(domain: "ManagedComponentDistributionSmokeTest.Configuration", code: 6)
        }
        let manifest = try ManagedComponentDistribution.verifiedManifest(
            data: manifestData,
            signatureData: signatureData,
            publicKeyBase64: publicKey
        )
        for component in ManagedComponent.allCases {
            _ = try ManagedComponentDistribution.artifact(for: component, in: manifest)
        }
    }

    private static func verifyTamperedActivationRecordIsIgnored(root: URL) throws {
        let componentRoot = root.appendingPathComponent("ffmpeg", isDirectory: true)
        let escapedExecutable = root.appendingPathComponent("outside/bin/ffmpeg")
        try FileManager.default.createDirectory(
            at: escapedExecutable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = FileManager.default.createFile(atPath: escapedExecutable.path, contents: Data("fixture".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: escapedExecutable.path)

        let tampered = ManagedComponentInstallation(
            version: "../../outside",
            executablePath: "bin/ffmpeg",
            previousVersion: nil
        )
        let data = try JSONEncoder().encode(tampered)
        try data.write(to: componentRoot.appendingPathComponent("current.json"), options: .atomic)
        guard ManagedComponentStore.executableURL(for: .ffmpeg, root: root) == nil else {
            throw NSError(domain: "ManagedComponentDistributionSmokeTest.Activation", code: 7)
        }
    }

    private static func verifySameVersionRepair(root: URL) throws {
        try installFixture(version: "9.0.1", root: root, contents: "rollback")
        try installFixture(version: "9.0.2", root: root, contents: "original")
        let executable = root.appendingPathComponent("ffmpeg/versions/9.0.2/bin/ffmpeg")
        try Data("altered".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        try installFixture(version: "9.0.2", root: root, contents: "repaired")
        let installation = ManagedComponentStore.activeInstallation(for: .ffmpeg, root: root)
        guard try String(contentsOf: executable, encoding: .utf8) == "repaired",
            installation?.version == "9.0.2",
            installation?.previousVersion == "9.0.1"
        else {
            throw NSError(domain: "ManagedComponentDistributionSmokeTest.Repair", code: 8)
        }
        try ManagedComponentStore.rollback(.ffmpeg, root: root)
        guard ManagedComponentStore.activeInstallation(for: .ffmpeg, root: root)?.version == "9.0.1" else {
            throw NSError(domain: "ManagedComponentDistributionSmokeTest.RepairRollback", code: 9)
        }
    }

    private static func installFixture(
        version: String,
        root: URL,
        contents: String = "fixture"
    ) throws {
        let extracted = root.appendingPathComponent("fixture-\(version)", isDirectory: true)
        let executable = extracted.appendingPathComponent("bin/ffmpeg")
        try FileManager.default.createDirectory(
            at: executable.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = FileManager.default.createFile(atPath: executable.path, contents: Data(contents.utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let artifact = ManagedComponentArtifact(
            component: .ffmpeg,
            version: version,
            architecture: ManagedComponentDistribution.currentArchitectureName(),
            minimumSystemVersion: "14.0",
            archiveURL: URL(string: "https://github.com/example/ffmpeg.zip")!,
            archiveSize: 128,
            sha256: String(repeating: "a", count: 64),
            executablePath: "bin/ffmpeg"
        )
        try ManagedComponentStore.install(extractedDirectory: extracted, artifact: artifact, root: root)
    }
}
