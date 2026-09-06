import Foundation
import UniformTypeIdentifiers

/// File admission only. The probe and playback checks still decide codec support.
enum MediaFileTypes {
    static let extensions = ["mkv", "mp4", "m4v", "mov", "ts", "mts", "m2ts"]

    static func accepts(_ url: URL) -> Bool {
        url.isFileURL && extensions.contains(url.pathExtension.lowercased())
    }

    static var contentTypes: [UTType] {
        // In particular, .ts can also mean source code. Ask for the movie type.
        Array(Set(extensions.compactMap { UTType(filenameExtension: $0, conformingTo: .movie) }))
    }
}
