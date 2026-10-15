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

    static func fixtureClock(_ lines: [String]) -> Double? {
        let expression = try? NSRegularExpression(pattern: #"^AC TIME ([0-9]{1,3})[.,]([0-9]{3,6})$"#)
        let values = lines.compactMap { line -> Double? in
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = expression?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                let secondsRange = Range(match.range(at: 1), in: text),
                let fractionRange = Range(match.range(at: 2), in: text),
                let seconds = Double(text[secondsRange]), let fraction = Double(text[fractionRange])
            else { return nil }
            let value = seconds + fraction / pow(10, Double(text[fractionRange].count))
            return (0...180).contains(value) ? value : nil
        }
        return values.count == 1 ? values[0] : nil
    }

    static func fixtureCueIndex(_ lines: [String], token: String) -> Int? {
        guard token.count == 6, token.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
        let expression = try? NSRegularExpression(pattern: "^aircillersubtitlecheck" + token + "([1-5])$")
        // A transport time is a separate OCR line, not more digits of the cue.
        let indices = lines.compactMap { line -> Int? in
            let text = line.lowercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }
            guard let match = expression?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                let range = Range(match.range(at: 1), in: text)
            else { return nil }
            return Int(text[range])
        }
        return indices.count == 1 ? indices[0] : nil
    }

    // Measure a stable sinusoid without knowing the requested fixture frequency.
    // Wrong pure tones remain measurements; uncertain buffers are not evidence.
    static func testToneFrequency(_ samples: [Float], channels: Int, sampleRate: Double) -> Double? {
        guard (1...8).contains(channels), samples.count >= channels * 64, samples.count <= 262_144,
            samples.count % channels == 0, sampleRate.isFinite, (8_000...192_000).contains(sampleRate),
            samples.allSatisfy(\.isFinite)
        else { return nil }
        let frames = samples.count / channels
        var mono = (0..<frames).map { frame in
            let offset = frame * channels
            return samples[offset..<(offset + channels)].reduce(0.0) { $0 + Double($1) } / Double(channels)
        }
        let mean = mono.reduce(0, +) / Double(frames)
        for index in mono.indices { mono[index] -= mean }
        guard mono.reduce(0, { $0 + $1 * $1 }) / Double(frames) > 1e-8 else { return nil }

        var crossings: [Double] = []
        for index in 1..<frames where mono[index - 1] <= 0 && mono[index] > 0 {
            crossings.append(Double(index - 1) - mono[index - 1] / (mono[index] - mono[index - 1]))
        }
        // Require four complete periods. A missed or spurious crossing must not
        // move the estimate, but most periods still need to agree within 5%.
        guard crossings.count >= 5 else { return nil }
        let periods = zip(crossings.dropFirst(), crossings).map(-)
        let sorted = periods.sorted()
        let median = (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
        guard median > 0, median.isFinite,
            Double(periods.filter { abs($0 - median) <= median * 0.05 }.count) >= Double(periods.count) * 0.75
        else { return nil }
        let frequency = sampleRate / median

        // A Hann-weighted sinusoid plus DC must explain at least 90% of AC
        // energy. This rejects mixtures/noise that happen to have regular zero
        // crossings, while reducing the influence of buffer-edge transients.
        var weight = 0.0
        var sumY = 0.0
        var sumS = 0.0
        var sumC = 0.0
        var sumYY = 0.0
        var sumSS = 0.0
        var sumCC = 0.0
        var sumYS = 0.0
        var sumYC = 0.0
        var sumSC = 0.0
        for index in mono.indices {
            let w = 0.5 - 0.5 * cos(2 * .pi * Double(index) / Double(frames - 1))
            let angle = 2 * .pi * frequency * Double(index) / sampleRate
            let s = sin(angle)
            let c = cos(angle)
            let y = mono[index]
            weight += w
            sumY += w * y
            sumS += w * s
            sumC += w * c
            sumYY += w * y * y
            sumSS += w * s * s
            sumCC += w * c * c
            sumYS += w * y * s
            sumYC += w * y * c
            sumSC += w * s * c
        }
        let yy = sumYY - sumY * sumY / weight
        let ss = sumSS - sumS * sumS / weight
        let cc = sumCC - sumC * sumC / weight
        let ys = sumYS - sumY * sumS / weight
        let yc = sumYC - sumY * sumC / weight
        let sc = sumSC - sumS * sumC / weight
        let determinant = ss * cc - sc * sc
        guard yy / weight > 1e-8, determinant > 0 else { return nil }
        let explained = (ys * ys * cc + yc * yc * ss - 2 * ys * yc * sc) / determinant
        guard explained / yy >= 0.9 else { return nil }
        return frequency
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
