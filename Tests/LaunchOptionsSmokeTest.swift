import Foundation

@main
struct LaunchOptionsSmokeTest {
    static func main() throws {
        let options = AirCillerLaunchOptions(arguments: [
            "AirCiller",
            "--skip-device-scan",
            "--autostart", "/Movies/Example Film.mkv",
            "--subtitle-index", "7",
            "--airplay-test", "http://127.0.0.1:8080/movie.mp4",
        ])

        guard options.skipsDeviceScan,
            options.autostartFileURL?.path == "/Movies/Example Film.mkv",
            options.subtitleStreamIndex == 7,
            options.directAirPlayTestURL?.absoluteString == "http://127.0.0.1:8080/movie.mp4"
        else {
            throw NSError(domain: "LaunchOptionsSmokeTest.Parsing", code: 1)
        }

        let incomplete = AirCillerLaunchOptions(arguments: ["AirCiller", "--autostart"])
        guard incomplete.autostartFileURL == nil,
            incomplete.subtitleStreamIndex == nil,
            incomplete.directAirPlayTestURL == nil,
            !incomplete.skipsDeviceScan
        else {
            throw NSError(domain: "LaunchOptionsSmokeTest.IncompleteOption", code: 2)
        }

        print("Opciones de arranque centralizadas: OK")
    }
}
