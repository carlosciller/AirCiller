import AppKit

@main
@MainActor
struct SubtitleOCRSmokeTest {
    static func main() async throws {
        let image = NSImage(size: NSSize(width: 1_280, height: 360))
        image.lockFocus()

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 82, weight: .bold),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black,
            .strokeWidth: -3,
        ]
        NSString(string: "HELLO AIR").draw(
            at: NSPoint(x: 360, y: 190),
            withAttributes: attributes
        )
        NSString(string: "SUBTITLE TEST").draw(
            at: NSPoint(x: 290, y: 80),
            withAttributes: attributes
        )
        image.unlockFocus()

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw NSError(domain: "SubtitleOCRSmokeTest.Image", code: 1)
        }
        let result = try await SubtitleOCRService.recognize(
            in: cgImage,
            preferredLanguages: ["en-US"]
        )
        let normalized = result.text
            .uppercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard normalized.contains("HELLO AIR"),
            normalized.contains("SUBTITLE TEST"),
            result.confidence >= 0.5
        else {
            throw NSError(
                domain: "SubtitleOCRSmokeTest.Recognition",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "OCR inesperado: \(result.text) (\(result.confidence))"]
            )
        }
        print("OCR local · dos líneas · \(Int(result.confidence * 100)) % · OK")
    }
}
