import Foundation

/// A value copy edited by the track popover and committed only on Apply.
struct TrackSettings: Equatable {
    var audioID: String?
    var subtitleID: String?
    var audioDelay: Double = 0
    var subtitleDelay: Double = 0
    var audioOutputMode: AudioOutputMode = .original
}
