import Foundation

struct AirCillerLaunchOptions: Equatable, Sendable {
    let directAirPlayTestURL: URL?
    let autostartFileURL: URL?
    let subtitleStreamIndex: Int?
    let skipsDeviceScan: Bool

    init(arguments: [String] = CommandLine.arguments) {
        directAirPlayTestURL = Self.value(after: "--airplay-test", in: arguments)
            .flatMap(URL.init(string:))
        autostartFileURL = Self.value(after: "--autostart", in: arguments)
            .map { URL(fileURLWithPath: $0) }
        subtitleStreamIndex = Self.value(after: "--subtitle-index", in: arguments)
            .flatMap(Int.init)
        skipsDeviceScan = arguments.contains("--skip-device-scan")
    }

    private static func value(after option: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: option),
            arguments.indices.contains(index + 1)
        else { return nil }
        return arguments[index + 1]
    }
}
