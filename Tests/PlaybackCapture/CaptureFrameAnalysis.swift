import CoreImage
import Foundation
import Vision

@main
struct CaptureFrameAnalysis {
    static func main() {
        do { try run() } catch {
            print("frameAnalysisFailed")
            exit(1)
        }
    }

    private static func run() throws {
        let args = CommandLine.arguments
        guard args.count == 3, args[1].hasPrefix("/") else { exit(2) }
        let tokens = args[2].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard (1...2).contains(tokens.count), Set(tokens).count == tokens.count,
            tokens.allSatisfy({ $0.count == 6 && $0.utf8.allSatisfy({ (48...57).contains($0) }) })
        else { exit(2) }
        let directory = URL(fileURLWithPath: args[1], isDirectory: true)
        let frames = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey]
        )
        .filter { $0.lastPathComponent.hasPrefix("frame-") && $0.pathExtension == "png" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !frames.isEmpty, frames.count <= CapturePolicy.maximumFrames else { exit(3) }
        let context = CIContext()
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        var previous: [UInt8]?
        var rows: [[String: Any]] = []
        for (index, frame) in frames.enumerated() {
            let info = try frame.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard frame.lastPathComponent == String(format: "frame-%03d.png", index + 1),
                info.isSymbolicLink != true, let size = info.fileSize, (1...3_000_000).contains(size),
                let image = CIImage(contentsOf: frame), image.extent.width <= 960, image.extent.height <= 540,
                image.extent.width >= 64, image.extent.height >= 36
            else { exit(4) }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            request.usesLanguageCorrection = false
            request.regionOfInterest = CGRect(x: 0, y: 0, width: 1, height: 0.5)
            try VNImageRequestHandler(url: frame).perform([request])
            let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            let flags = CapturePolicy.cueFlags(lines, token: tokens[0])
            let recognizedTokens = tokens.filter { CapturePolicy.cueFlags(lines, token: $0).expected }
            let small = image.transformed(
                by: CGAffineTransform(scaleX: 64 / image.extent.width, y: 36 / image.extent.height))
            var pixels = [UInt8](repeating: 0, count: 64 * 36 * 4)
            pixels.withUnsafeMutableBytes {
                context.render(
                    small, toBitmap: $0.baseAddress!, rowBytes: 64 * 4,
                    bounds: CGRect(x: 0, y: 0, width: 64, height: 36), format: .RGBA8, colorSpace: colorSpace)
            }
            // Exclude subtitles and the transport bar from the motion measurement.
            var central: [UInt8] = []
            for y in 16..<32 {
                for x in 6..<58 {
                    let offset = (y * 64 + x) * 4
                    central.append(UInt8((Int(pixels[offset]) + Int(pixels[offset + 1]) + Int(pixels[offset + 2])) / 3))
                }
            }
            let difference =
                zip(central, previous ?? central).reduce(0.0) { $0 + abs(Double($1.0) - Double($1.1)) }
                / Double(central.count)
            previous = central
            let colors = [5, 16, 27, 37, 48, 59].map { x -> (Double, Double, Double) in
                let offset = (27 * 64 + x) * 4
                return (Double(pixels[offset]), Double(pixels[offset + 1]), Double(pixels[offset + 2]))
            }
            rows.append([
                "frame": frame.lastPathComponent, "anyCue": flags.any, "expectedCue": flags.expected,
                "centralDifference": difference, "testPattern": CapturePolicy.hasTestPattern(colors),
                "cueTokens": recognizedTokens,
            ])
        }
        // Do not print arbitrary recognized text, movie names or source paths.
        print(String(decoding: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), as: UTF8.self))
    }
}
