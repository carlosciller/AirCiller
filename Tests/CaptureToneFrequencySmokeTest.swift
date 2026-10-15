import Foundation

@main
struct CaptureToneFrequencySmokeTest {
    static func main() throws {
        for rate in [16_000.0, 44_100, 48_000, 96_000] {
            for frequency in [395.0, 440, 550, 880, 931, 1_000] {
                for phase in [0.0, 0.3, 1.7] {
                    let clean = tone(frequency, rate: rate, phase: phase)
                    try measured(clean, rate: rate, frequency: frequency, name: "pure tone")
                    try measured(clean.map { $0 * 0.01 }, rate: rate, frequency: frequency, name: "quiet tone")
                    try measured(clean.map { $0 + 0.2 }, rate: rate, frequency: frequency, name: "DC offset")
                    let envelope = clean.enumerated().map { index, value in
                        value * Float(0.2 + 0.8 * Double(index) / Double(clean.count - 1))
                    }
                    try measured(envelope, rate: rate, frequency: frequency, name: "gain envelope")
                    var edge = clean
                    for index in 0..<max(1, clean.count / 20) {
                        edge[index] += Float(0.4 * exp(-Double(index) / Double(clean.count / 100 + 1)))
                    }
                    try measured(edge, rate: rate, frequency: frequency, name: "buffer-edge transient")
                }
            }
        }

        let rate = 48_000.0
        let a = tone(440, rate: rate, phase: 0.3)
        let b = tone(880, rate: rate, phase: 0.8)
        for gain in [Float(0.5), 1, 2] {
            try rejected(zip(a, b).map { $0 + gain * $1 }, rate: rate, name: "mixed fixture tones")
        }
        let switched = Array(a.prefix(a.count / 2)) + Array(b.suffix(b.count / 2))
        try rejected(switched, rate: rate, name: "tone change inside buffer")
        let chirp = (0..<a.count).map { index -> Float in
            let time = Double(index) / rate
            return Float(0.1 * sin(2 * .pi * (440 * time + 0.5 * 11_000 * time * time)))
        }
        try rejected(chirp, rate: rate, name: "frequency sweep")
        var dropout = a
        let middle = dropout.count / 2
        for index in middle..<(middle + Int(rate / 440)) { dropout[index] = 0 }
        try correctOrUnknown(dropout, rate: rate, frequency: 440, name: "missing cycle")
        var state: UInt64 = 0x1234_5678
        let noise = a.map { _ -> Float in
            state = state &* 6_364_136_223_846_793_005 &+ 1
            return Float(Double(state >> 32) / Double(UInt32.max) - 0.5) * 0.2
        }
        try rejected(noise, rate: rate, name: "noise")
        try rejected(Array(repeating: 0, count: a.count), rate: rate, name: "silence")
        try rejected(Array(repeating: 0.2, count: a.count), rate: rate, name: "DC only")
        try rejected(Array(repeating: .nan, count: a.count), rate: rate, name: "nonfinite samples")
        try rejected(Array(a.prefix(64)), rate: rate, name: "too few complete cycles")
        precondition(CapturePolicy.testToneFrequency(a, channels: 0, sampleRate: rate) == nil)
        precondition(CapturePolicy.testToneFrequency(a, channels: 1, sampleRate: .nan) == nil)
        print("Capture tone detector: known/wrong tones, envelopes, DC, transients, mixes and invalid input: OK")
    }

    private static func tone(_ frequency: Double, rate: Double, phase: Double) -> [Float] {
        (0..<Int(rate * 0.04)).map { Float(0.1 * sin(2 * .pi * frequency * Double($0) / rate + phase)) }
    }

    private static func measured(_ samples: [Float], rate: Double, frequency: Double, name: String) throws {
        let stereo = samples.flatMap { [$0, $0] }
        guard let measured = CapturePolicy.testToneFrequency(stereo, channels: 2, sampleRate: rate),
            abs(measured - frequency) < 2
        else { throw NSError(domain: "CaptureToneFrequency.\(name).\(frequency).\(rate)", code: 1) }
    }

    private static func correctOrUnknown(_ samples: [Float], rate: Double, frequency: Double, name: String) throws {
        if let measured = CapturePolicy.testToneFrequency(samples, channels: 1, sampleRate: rate),
            abs(measured - frequency) >= 2
        {
            throw NSError(domain: "CaptureToneFrequency.\(name).inventedFrequency", code: 1)
        }
    }

    private static func rejected(_ samples: [Float], rate: Double, name: String) throws {
        guard CapturePolicy.testToneFrequency(samples, channels: 1, sampleRate: rate) == nil else {
            throw NSError(domain: "CaptureToneFrequency.\(name).mustRemainUnknown", code: 1)
        }
    }
}
