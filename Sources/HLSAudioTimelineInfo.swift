import Foundation

struct HLSAudioTimelineInfo: Codable, Sendable {
    static let fileName = "audio-timeline.json"
    let version: Int
    let sourceDuration: Double
    let presentationDuration: Double
    let timestampOrigin: Double
    let videoContentOffset: Double

    func validate() throws {
        guard version == 1, sourceDuration.isFinite, sourceDuration > 0,
            presentationDuration.isFinite, presentationDuration > 0,
            timestampOrigin.isFinite, timestampOrigin >= 0, timestampOrigin < 95_000,
            videoContentOffset.isFinite, videoContentOffset >= 0, videoContentOffset <= presentationDuration
        else { throw AirCillerError.invalidVODPackage(L10n.text("El mapa temporal del audio no es válido.")) }
    }

    static func load(directory: URL) throws -> Self? {
        let url = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: 8193), data.count <= 8192 else {
            throw AirCillerError.invalidVODPackage(L10n.text("El mapa temporal del audio no es válido."))
        }
        let info = try JSONDecoder().decode(Self.self, from: data)
        try info.validate()
        return info
    }
}
