import CoreGraphics
import Foundation
@preconcurrency import Vision

struct SubtitleOCRResult: Equatable, Sendable {
    let text: String
    let confidence: Float

    var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Local OCR for subtitle bitmaps decoded from PGS or VobSub tracks.
///
/// This service deliberately has no knowledge of video containers or AirPlay.
/// Keeping OCR isolated lets the bitmap decoder be added later without changing
/// either of AirCiller's verified playback routes.
enum SubtitleOCRService {
    static func recognize(
        in image: CGImage,
        preferredLanguages: [String] = []
    ) async throws -> SubtitleOCRResult {
        let preparedImage = flattenedOnBlack(image) ?? image
        if #available(macOS 15.0, *) {
            return try await recognizeModern(
                in: preparedImage,
                preferredLanguages: preferredLanguages
            )
        }
        return try recognizeLegacy(
            in: preparedImage,
            preferredLanguages: preferredLanguages
        )
    }

    @available(macOS 15.0, *)
    private static func recognizeModern(
        in image: CGImage,
        preferredLanguages: [String]
    ) async throws -> SubtitleOCRResult {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeightFraction = 0.012
        request.automaticallyDetectsLanguage = preferredLanguages.isEmpty
        request.recognitionLanguages = preferredLanguages.map(Locale.Language.init(identifier:))

        let observations = try await request.perform(on: image)
        let lines = observations.compactMap { observation -> OCRLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return OCRLine(
                text: text,
                confidence: candidate.confidence,
                box: observation.boundingBox.cgRect
            )
        }
        return result(from: lines)
    }

    private static func recognizeLegacy(
        in image: CGImage,
        preferredLanguages: [String]
    ) throws -> SubtitleOCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0.012
        if !preferredLanguages.isEmpty {
            request.recognitionLanguages = preferredLanguages
        }

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        try handler.perform([request])

        let lines = (request.results ?? []).compactMap { observation -> OCRLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return OCRLine(text: text, confidence: candidate.confidence, box: observation.boundingBox)
        }
        return result(from: lines)
    }

    private static func result(from lines: [OCRLine]) -> SubtitleOCRResult {
        let orderedLines = lines.sorted(by: readingOrder)
        guard !orderedLines.isEmpty else {
            return SubtitleOCRResult(text: "", confidence: 0)
        }
        let confidence = orderedLines.reduce(Float.zero) { $0 + $1.confidence } / Float(orderedLines.count)
        let text = orderedLines.map(\.text).joined(separator: "\n")
        return SubtitleOCRResult(
            text: SubtitleOCRTextNormalizer.normalize(text),
            confidence: confidence
        )
    }

    private struct OCRLine {
        let text: String
        let confidence: Float
        let box: CGRect
    }

    private static func readingOrder(_ left: OCRLine, _ right: OCRLine) -> Bool {
        let sameLineTolerance = max(left.box.height, right.box.height) * 0.45
        if abs(left.box.midY - right.box.midY) > sameLineTolerance {
            return left.box.midY > right.box.midY
        }
        return left.box.minX < right.box.minX
    }

    /// PGS and VobSub bitmaps normally contain transparent pixels around the
    /// glyphs. A stable opaque background makes Vision's recognition much less
    /// dependent on the frame that happened to be behind the subtitle.
    private static func flattenedOnBlack(_ image: CGImage) -> CGImage? {
        guard
            let context = CGContext(
                data: nil,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(bounds)
        context.draw(image, in: bounds)
        return context.makeImage()
    }
}
