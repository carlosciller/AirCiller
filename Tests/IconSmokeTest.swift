import AppKit
import Foundation

@main
struct IconSmokeTest {
    enum Failure: Error { case invalid(String) }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure.invalid(message) }
    }

    static func image(_ data: Data) throws -> NSBitmapImageRep {
        guard let image = NSBitmapImageRep(data: data) else { throw Failure.invalid("Invalid PNG") }
        return image
    }

    static func rgba(_ image: NSBitmapImageRep, _ x: Int, _ y: Int) throws -> [CGFloat] {
        guard let color = image.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else {
            throw Failure.invalid("Unreadable pixel")
        }
        return [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent]
    }

    static func representationMap(_ data: Data) throws -> [String: Data] {
        func uint32(_ position: Int) -> Int {
            data[position..<position + 4].reduce(0) { ($0 << 8) | Int($1) }
        }
        try require(data.count >= 8 && data.prefix(4) == Data("icns".utf8), "ICNS header")
        try require(uint32(4) == data.count, "ICNS total length")
        var offset = 8
        var representations: [String: Data] = [:]
        while offset < data.count {
            try require(offset + 8 <= data.count, "Truncated ICNS element")
            let length = uint32(offset + 4)
            try require(length > 8 && offset + length <= data.count, "Invalid ICNS element length")
            let key = String(decoding: data[offset..<offset + 4], as: UTF8.self)
            try require(representations[key] == nil, "Duplicate ICNS element")
            representations[key] = data.subdata(in: offset + 8..<offset + length)
            offset += length
        }
        return representations
    }

    static func validateColors(production: NSBitmapImageRep, test: NSBitmapImageRep, size: Int) throws {
        try require(
            production.pixelsWide == size && production.pixelsHigh == size
                && test.pixelsWide == size && test.pixelsHigh == size,
            "Wrong representation dimensions: \(size)"
        )
        // Sample the same production coordinates at every native representation.
        // Coordinates use PNG's top-down orientation, with margin from the seam.
        func sample(_ image: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) throws -> [CGFloat] {
            try rgba(image, Int(CGFloat(size) * x), Int(CGFloat(size) * y))
        }
        let originalCorner = try sample(production, 0.25, 0.25)
        let testCorner = try sample(test, 0.25, 0.25)
        try require(zip(originalCorner, testCorner).allSatisfy { abs($0 - $1) < 0.005 }, "Original half changed")
        let purple = try sample(test, 0.78, 0.74)
        try require(purple[2] > purple[0] && purple[0] > purple[1], "Purple test background missing")
        let white = try sample(test, 0.30, 0.41)
        try require(white[0] > 0.9 && white[1] > 0.9 && white[2] > 0.9, "White original-side glyph missing")
        let yellow = try sample(test, 0.69, 0.44)
        try require(yellow[0] > 0.85 && yellow[1] > 0.65 && yellow[2] < 0.4, "Yellow test-side glyph missing")
        let corner = try sample(test, 0, 0)
        try require(corner[3] == 0, "Transparent margin lost")

        // The recoloring must not move or enlarge the existing silhouette/shadow.
        // Antialiasing can change edge alpha by one pixel when applying a clip.
        for row in 0..<size {
            for column in 0..<size {
                let before = try rgba(production, column, row)
                let after = try rgba(test, column, row)
                if before[3] == 0 { try require(after[3] == 0, "Test icon expands outside the production shape") }
                if before[3] > 0.99 { try require(after[3] > 0.99, "Test icon introduces a hole") }
            }
        }
    }

    static func main() throws {
        let project = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let generator = project.appendingPathComponent(".build/tests/make-icon")
        let output = project.appendingPathComponent(".build/tests/icon-output", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        func generate(_ name: String, test: Bool) throws -> (png: Data, icns: Data) {
            let png = output.appendingPathComponent("\(name).png")
            let icns = output.appendingPathComponent("\(name).icns")
            let process = Process()
            process.executableURL = generator
            process.arguments = (test ? ["--test"] : []) + [png.path, icns.path]
            try process.run()
            process.waitUntilExit()
            try require(process.terminationStatus == 0, "Icon generator failed")
            return (try Data(contentsOf: png), try Data(contentsOf: icns))
        }

        let production = try generate("production", test: false)
        let test = try generate("test", test: true)
        let repeated = try generate("test-repeat", test: true)
        try require(test.png == repeated.png && test.icns == repeated.icns, "Test icon is nondeterministic")
        try require(production.png != test.png && production.icns != test.icns, "Test icon is indistinguishable")

        // The shipping resources are the approved production artwork. Compare
        // decoded pixels so incidental PNG metadata cannot cause a false failure.
        let reference = try image(Data(contentsOf: project.appendingPathComponent("Resources/AirCiller-1024.png")))
        let current = try image(production.png)
        try require(
            current.pixelsWide == reference.pixelsWide && current.pixelsHigh == reference.pixelsHigh, "Production size")
        for row in 0..<current.pixelsHigh {
            for column in 0..<current.pixelsWide {
                let old = try rgba(reference, column, row)
                let new = try rgba(current, column, row)
                try require(zip(old, new).allSatisfy { abs($0 - $1) <= 3.0 / 255 }, "Production artwork changed")
            }
        }

        let expected = [
            "ic07": 128, "ic08": 256, "ic09": 512, "ic10": 1024,
            "ic11": 32, "ic12": 64, "ic13": 256, "ic14": 512,
        ]
        let originalRepresentations = try representationMap(production.icns)
        let testRepresentations = try representationMap(test.icns)
        try require(Set(originalRepresentations.keys) == Set(expected.keys), "Production ICNS representations changed")
        try require(Set(testRepresentations.keys) == Set(expected.keys), "Incomplete test ICNS")
        for (key, size) in expected.sorted(by: { $0.key < $1.key }) {
            let original = try image(originalRepresentations[key]!)
            let variant = try image(testRepresentations[key]!)
            try validateColors(production: original, test: variant, size: size)
            try testRepresentations[key]!.write(to: output.appendingPathComponent("test-\(size).png"))
        }
        print("Icon checks: production preserved, test variant deterministic, all 8 representations verified")
    }
}
