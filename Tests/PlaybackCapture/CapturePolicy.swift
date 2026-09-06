import Foundation

struct CaptureSourceIdentity {
    var uniqueID: String
    var name: String
    var model: String
    var external: Bool
    var transport: UInt32
    var muxed: Bool
    var video: Bool
    var audio: Bool
    var continuityCamera: Bool
    var connected: Bool

    func matches(approvedID: String, approvedName: String) -> Bool {
        !approvedID.isEmpty && !approvedName.isEmpty && uniqueID == approvedID && name == approvedName
            && model == "iOS Device" && external && transport == 0x6f74_6872
            && muxed && !video && !audio && !continuityCamera && connected
    }
}

enum CapturePolicy {
    static let maximumSeconds = 120.0
    static let maximumFrames = 240
    static let maximumRows = 1_024
    static let maximumBytes = 128 * 1_024 * 1_024

    static func safeLabel(_ text: String, maximumBytes: Int) -> Bool {
        !text.isEmpty && text.utf8.count <= maximumBytes
            && text.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 }
    }

    static func cueFlags(_ lines: [String], token: String) -> (any: Bool, expected: Bool) {
        let text = lines.joined().lowercased().filter { $0.isASCII && $0.isLetter || $0.isNumber }
        let prefix = "aircillersubtitlecheck"
        return (text.contains(prefix), text.contains(prefix + token))
    }

    // A lightweight check for the two known fixture tones, not general audio identification.
    static func testToneFrequency(_ samples: [Float], channels: Int, sampleRate: Double) -> Double? {
        guard (1...8).contains(channels), samples.count >= channels * 64, samples.count <= 262_144,
            samples.count % channels == 0, sampleRate.isFinite, (8_000...192_000).contains(sampleRate),
            samples.allSatisfy(\.isFinite)
        else { return nil }
        var crossings: [Double] = []
        var previous = 0.0
        var power = 0.0
        let frames = samples.count / channels
        for frame in 0..<frames {
            let offset = frame * channels
            let value = samples[offset..<(offset + channels)].reduce(0.0) { $0 + Double($1) } / Double(channels)
            power += value * value
            if frame > 0, previous <= 0, value > 0 {
                crossings.append(Double(frame - 1) + (-previous / (value - previous)))
            }
            previous = value
        }
        guard power / Double(frames) > 1e-8, crossings.count >= 3,
            let first = crossings.first, let last = crossings.last, last > first
        else { return nil }
        return Double(crossings.count - 1) * sampleRate / (last - first)
    }

    // The generated SDR fixture has six color bands. This rejects a moving
    // screensaver or player controls as proof that the no-subtitle case arrived.
    static func hasTestPattern(_ rgb: [(Double, Double, Double)]) -> Bool {
        guard rgb.count == 6 else { return false }
        let expected = [
            (true, false, false), (false, true, false), (true, true, false),
            (false, false, true), (true, false, true), (false, true, true),
        ]
        return zip(rgb, expected).allSatisfy { value, high in
            let channels = [value.0, value.1, value.2]
            let flags = [high.0, high.1, high.2]
            let bright = zip(channels, flags).filter(\.1).map(\.0)
            let dark = zip(channels, flags).filter { !$0.1 }.map(\.0)
            return channels.allSatisfy { $0.isFinite && (0...255).contains($0) }
                && (bright.min() ?? 0) > 30 && (bright.min() ?? 0) > (dark.max() ?? 0) * 1.6
        }
    }
}
