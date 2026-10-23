import Foundation

/// The authenticated bridge accepts this closed command vocabulary. Library
/// and receiver identifiers are opaque mappings, never filesystem paths.
enum RemoteCommand: Codable, Equatable, Sendable {
    case status
    case search(query: String)
    case play(itemID: UUID, fromBeginning: Bool)
    case pause
    case resume
    case stop
    case next
    case seek(seconds: Double)
    case skip(seconds: Double)
    case receivers
    case selectReceiver(id: UUID)
    case tracks
    case selectTracks(audioID: String?, subtitleID: String?)
    case synchronize(audio: Double, subtitles: Double)
    case preferences
    case setLanguages(audio: String, subtitles: String, persistent: Bool)
    case resolveConversion(decisionID: UUID, approve: Bool, equivalentEpisodes: Bool)
    case operation(id: UUID)
    case cancelOperation(id: UUID)

    enum Invalid: Error { case argument }

    var mutates: Bool {
        switch self {
        case .status, .search, .receivers, .tracks, .preferences, .operation: false
        default: true
        }
    }

    /// Called before ledger admission and coordinator access. Syntactic validity
    /// does not establish that an identifier belongs to the current session.
    func validatedEncoding() throws -> Data {
        switch self {
        case .search(let query):
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                query.utf8.count <= 256
            else { throw Invalid.argument }
        case .seek(let seconds):
            guard seconds.isFinite, seconds >= 0, seconds <= 604_800 else { throw Invalid.argument }
        case .skip(let seconds):
            guard seconds.isFinite, abs(seconds) <= 3_600 else { throw Invalid.argument }
        case .synchronize(let audio, let subtitles):
            guard audio.isFinite, subtitles.isFinite, (-5...5).contains(audio),
                (-10...10).contains(subtitles)
            else { throw Invalid.argument }
        case .selectTracks(let audio, let subtitles):
            for identifier in [audio, subtitles].compactMap({ $0 }) {
                guard !identifier.isEmpty, identifier.utf8.count <= 128,
                    !identifier.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
                else { throw Invalid.argument }
            }
        case .setLanguages(let audio, let subtitles, _):
            for language in [audio, subtitles] {
                guard
                    language.isEmpty
                        || (language.utf8.count == 3
                            && language.utf8.allSatisfy({ (97...122).contains($0) }))
                else { throw Invalid.argument }
            }
        default: break
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}
