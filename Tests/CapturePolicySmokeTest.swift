import Foundation

@main
struct CapturePolicySmokeTest {
    static func main() throws {
        let approved = CaptureSourceIdentity(
            uniqueID: "approved-screen", name: "Test receiver", model: "iOS Device",
            external: true, transport: 0x6f74_6872, muxed: true, video: false, audio: false,
            continuityCamera: false, connected: true)
        func accepts(_ value: CaptureSourceIdentity) -> Bool {
            value.matches(approvedID: "approved-screen", approvedName: "Test receiver")
        }
        try expect(accepts(approved), "Exact approved screen")
        let mutations: [(inout CaptureSourceIdentity) -> Void] = [
            { $0.uniqueID = "different-screen" }, { $0.name = "Different receiver" },
            { $0.model = "Camera" }, { $0.external = false }, { $0.transport = 0 },
            { $0.muxed = false }, { $0.video = true }, { $0.audio = true },
            { $0.continuityCamera = true }, { $0.connected = false },
        ]
        for mutate in mutations {
            var rejected = approved
            mutate(&rejected)
            try expect(!accepts(rejected), "Reject changed source before creating input")
        }
        try expect(!approved.matches(approvedID: "", approvedName: "Test receiver"), "No default source")
        try expect(!CapturePolicy.safeLabel("camera\nother", maximumBytes: 256), "Control characters")
        try expect(
            !CapturePolicy.safeLabel(String(repeating: "x", count: 257), maximumBytes: 256), "Bounded identifiers")
        let cue = CapturePolicy.cueFlags(["AirCiller subtitle check: 123456-1"], token: "123456")
        try expect(cue.any && cue.expected, "Expected per-case cue")
        let stale = CapturePolicy.cueFlags(["AirCiller subtitle check: 654321-1"], token: "123456")
        try expect(stale.any && !stale.expected, "A stale cue is not a pass")
        try expect(!CapturePolicy.cueFlags(["Player 00:15"], token: "123456").any, "Controls are not subtitles")
        let pattern = [
            (200.0, 0.0, 0.0), (0.0, 180.0, 0.0), (180.0, 190.0, 0.0),
            (0.0, 0.0, 180.0), (170.0, 0.0, 180.0), (0.0, 170.0, 180.0),
        ]
        try expect(CapturePolicy.hasTestPattern(pattern), "Synthetic fixture color bands")
        try expect(!CapturePolicy.hasTestPattern(Array(repeating: (90, 90, 90), count: 6)), "Player overlay rejected")
        try expect(!CapturePolicy.hasTestPattern(Array(repeating: (0, 0, 0), count: 6)), "Black output rejected")
        for frequency in [440.0, 880.0] {
            let mono = (0..<1_600).map { Float(0.1 * sin(2 * Double.pi * frequency * Double($0) / 16_000 + 0.3)) }
            let stereo = mono.flatMap { [$0, $0] }
            let measured = CapturePolicy.testToneFrequency(stereo, channels: 2, sampleRate: 16_000)
            try expect(measured.map { abs($0 - frequency) < 1 } == true, "Distinguish original fixture audio tracks")
        }
        try expect(
            CapturePolicy.testToneFrequency(Array(repeating: 0, count: 1_600), channels: 2, sampleRate: 16_000) == nil,
            "Silence is not a tone")
        try expect(
            CapturePolicy.testToneFrequency(Array(repeating: .nan, count: 1_600), channels: 2, sampleRate: 16_000)
                == nil, "Reject invalid PCM")
        try expect(
            CapturePolicy.testToneFrequency([1, 2], channels: 0, sampleRate: 16_000) == nil,
            "Reject invalid channel layout")
        print("Capture identity, camera rejection, cue identity and fixture evidence: OK")
    }

    private static func expect(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "CapturePolicy.\(message)", code: 1) }
    }
}
