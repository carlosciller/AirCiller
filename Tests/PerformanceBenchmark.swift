import Foundation

@main
struct PerformanceBenchmark {
    static func main() throws {
        let header =
            "[Events]\nFormat: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text\n"
        let variants = [
            #"Plain text & Unicode: café 日本語 🎵"#,
            #"{\i1}Hello{\i0}\NSecond line"#,
            #"{\an8\pos(192,30)\b1}Sign{\b0}"#,
            #"{\move(10,20,30,40)\k20}Song"#,
            #"{\an5\u1}Legacy{\r} reset"#,
            #"{\p1}m 0 0 l 10 10{\p0}Visible"#,
            #"{\AN7\POS(15,25)\I1}Uppercase{\I0}"#,
            #"{\clip(0,0,10,10)\fad(50,50)}Effect"#,
            #"{\an2\an8\pos(1,2)\pos(3,4)}Repeated"#,
            #"{\p1\p0\b1\b0\u1}Ordered styles{\r}"#,
        ]
        let source =
            header
            + (0..<2_000).map { index in
                "Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,\(variants[index % variants.count])"
            }.joined(separator: "\n")
        let expected = ASSSubtitleConverter.convert(source)
        try Data(expected.webVTT.utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        var assTimes: [Double] = []
        var bufferTimes: [Double] = []
        let chunk = Data((0..<4_096).map { UInt8(truncatingIfNeeded: $0) })
        let expectedTail = (0..<256).reduce(into: Data()) { data, _ in data.append(chunk) }
        for _ in 0..<7 {
            var start = ContinuousClock.now
            let result = ASSSubtitleConverter.convert(source)
            assTimes.append(milliseconds(start.duration(to: .now)))
            precondition(result == expected)
            let buffer = ProcessDataBuffer(maximumBytes: 1_048_576)
            start = .now
            for _ in 0..<8_192 { buffer.append(chunk) }
            let snapshot = buffer.snapshot
            bufferTimes.append(milliseconds(start.duration(to: .now)))
            precondition(snapshot == expectedTail)
        }
        print("ASS 2000 cues ms: \(assTimes)")
        print("Buffer 32 MiB, 4 KiB writes, 1 MiB tail ms: \(bufferTimes)")
        print("Median ASS: \(assTimes.sorted()[3]); buffer: \(bufferTimes.sorted()[3])")
    }

    static func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }
}
