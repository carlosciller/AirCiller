import Foundation

enum AirPlayRuntimeProbe {
    static let marker = "AirCiller AirPlay engine ready"

    static var arguments: [String] {
        [
            "-c",
            "import pyatv, aiohttp, requests, zeroconf; print('\(marker)')",
        ]
    }

    static func environment(
        vendorDirectory: URL,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base
        environment["PYTHONPATH"] = vendorDirectory.path
        environment["PYTHONWARNINGS"] = "ignore:urllib3 v2 only supports OpenSSL"
        environment["PYTHONPYCACHEPREFIX"] =
            FileManager.default.temporaryDirectory
            .appendingPathComponent("AirCiller-PythonCache", isDirectory: true).path
        return environment
    }

    static func isReady(status: Int32, output: String) -> Bool {
        status == 0 && output.contains(marker)
    }
}
