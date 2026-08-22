import Foundation

@main
struct HDRConfigurationSmokeTest {
    static func main() throws {
        guard CommandLine.arguments.count == 4 else {
            throw NSError(domain: "HDRConfigurationSmokeTest.Usage", code: 2)
        }
        let sourceInitialization = URL(fileURLWithPath: CommandLine.arguments[1])
        let firstSegment = URL(fileURLWithPath: CommandLine.arguments[2])
        let output = URL(fileURLWithPath: CommandLine.arguments[3])

        try? FileManager.default.removeItem(at: output)
        try FileManager.default.copyItem(at: sourceInitialization, to: output)
        let fileTypeChanged = try HDRConfigurationInjector.normalizeHLSFileType(
            initializationSegment: output
        )
        let changed = try HDRConfigurationInjector.injectStaticMetadata(
            initializationSegment: output,
            firstMediaSegment: firstSegment
        )
        print(fileTypeChanged ? "HLS file type normalized" : "HLS file type already normalized")
        print(changed ? "HDR metadata injected" : "HDR metadata already present")
    }
}
