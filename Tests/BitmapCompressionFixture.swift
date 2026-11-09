import AppKit

@main
@MainActor
struct BitmapCompressionFixture {
    static func main() throws {
        let image = NSImage(size: NSSize(width: 1920, height: 1080))
        image.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill(using: .copy)
        for (index, text) in ["AirCiller subtitle preparation", "♪ A second line with music ♪"].enumerated() {
            NSString(string: text).draw(
                at: NSPoint(x: 300, y: 160 - 65 * index),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 52, weight: .semibold),
                    .foregroundColor: NSColor.white,
                    .strokeColor: NSColor.black,
                    .strokeWidth: -3,
                ])
        }
        image.unlockFocus()
        guard let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
            let data = NSBitmapImageRep(cgImage: bitmap).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
