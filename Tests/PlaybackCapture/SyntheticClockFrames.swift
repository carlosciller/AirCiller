import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Development-only fixture artwork. It opens no UI or capture input.
@main
struct SyntheticClockFrames {
    static func main() throws {
        guard CommandLine.arguments.count == 2, CommandLine.arguments[1].hasPrefix("/") else {
            throw Failure.invalidDirectory
        }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw Failure.invalidDirectory }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, 80, nil)
        for index in 0..<600 {
            guard
                let context = CGContext(
                    data: nil, width: 1120, height: 128, bitsPerComponent: 8, bytesPerRow: 1120 * 4,
                    space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw Failure.renderFailed }
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 1120, height: 128))
            let text = String(format: "AC TIME %.3f", locale: Locale(identifier: "en_US_POSIX"), Double(index) / 10)
            let attributed = NSAttributedString(
                string: text,
                attributes: [
                    NSAttributedString.Key(kCTFontAttributeName as String): font,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
                ])
            context.textPosition = CGPoint(x: 20, y: 28)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            let target = directory.appendingPathComponent(String(format: "clock-%04d.png", index))
            guard let image = context.makeImage(),
                let destination = CGImageDestinationCreateWithURL(
                    target as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { throw Failure.renderFailed }
            CGImageDestinationAddImage(destination, image, nil)
            guard CGImageDestinationFinalize(destination) else { throw Failure.renderFailed }
        }
    }

    private enum Failure: Error { case invalidDirectory, renderFailed }
}
