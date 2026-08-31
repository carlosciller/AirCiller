import Foundation

@main
struct AirPlayRuntimeProbeSmokeTest {
    static func main() throws {
        let vendor = URL(fileURLWithPath: "/private/tmp/AirCiller Vendor")
        let environment = AirPlayRuntimeProbe.environment(
            vendorDirectory: vendor,
            base: ["PATH": "/usr/bin"]
        )
        guard AirPlayRuntimeProbe.arguments.contains(where: { $0.contains("import pyatv") }),
            environment["PYTHONPATH"] == vendor.path,
            AirPlayRuntimeProbe.isReady(status: 0, output: AirPlayRuntimeProbe.marker),
            !AirPlayRuntimeProbe.isReady(status: 1, output: AirPlayRuntimeProbe.marker),
            !AirPlayRuntimeProbe.isReady(status: 0, output: "Python 3.13.15")
        else {
            throw NSError(domain: "AirPlayRuntimeProbeSmokeTest", code: 1)
        }

        print("AirPlay readiness requires imports from the bundled engine, not only Python: OK")
    }
}
