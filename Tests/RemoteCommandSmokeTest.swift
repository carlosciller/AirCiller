import Foundation

@main
struct RemoteCommandSmokeTest {
    static func main() throws {
        let id = UUID()
        let valid: [RemoteCommand] = [
            .status, .search(query: "Edgerunners"), .play(itemID: id, fromBeginning: false),
            .pause, .resume, .stop, .next, .seek(seconds: 90), .skip(seconds: -30),
            .receivers, .selectReceiver(id: id), .tracks,
            .selectTracks(audioID: "audio-1", subtitleID: nil),
            .synchronize(audio: -5, subtitles: 10), .preferences,
            .setLanguages(audio: "jpn", subtitles: "spa", persistent: false),
            .resolveConversion(decisionID: id, approve: true, equivalentEpisodes: true),
            .operation(id: id), .cancelOperation(id: id),
        ]
        for command in valid {
            let encoded = try command.validatedEncoding()
            let decoded = try JSONDecoder().decode(RemoteCommand.self, from: encoded)
            precondition(decoded == command)
        }
        let invalid: [RemoteCommand] = [
            .search(query: "  "), .search(query: String(repeating: "x", count: 257)),
            .seek(seconds: -1), .skip(seconds: .infinity), .seek(seconds: .nan),
            .synchronize(audio: 5.1, subtitles: 0), .synchronize(audio: 0, subtitles: -10.1),
            .selectTracks(audioID: "\n", subtitleID: nil),
            .setLanguages(audio: "Japanese", subtitles: "spa", persistent: true),
        ]
        for command in invalid {
            do {
                _ = try command.validatedEncoding()
                preconditionFailure("Invalid command accepted")
            } catch RemoteCommand.Invalid.argument {}
        }
        precondition(!RemoteCommand.status.mutates && RemoteCommand.stop.mutates)
        print("Remote command contract: OK")
    }
}
