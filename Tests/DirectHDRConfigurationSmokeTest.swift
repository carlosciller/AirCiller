import Foundation

@main
struct DirectHDRConfigurationSmokeTest {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            throw NSError(domain: "DirectHDRConfigurationSmokeTest.Usage", code: 2)
        }
        let source = URL(fileURLWithPath: CommandLine.arguments[1])
        let output = URL(fileURLWithPath: CommandLine.arguments[2])

        try? FileManager.default.removeItem(at: output)
        try FileManager.default.copyItem(at: source, to: output)
        let changed = try HDRConfigurationInjector.injectStaticMetadataIntoDirectFile(output)
        print(changed ? "HDR metadata updated in reserved header" : "HDR metadata already present")
    }
}
