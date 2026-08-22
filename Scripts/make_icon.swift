import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Uso: make_icon.swift destino.png destino.icns\n", stderr)
    exit(2)
}

let pngURL = URL(fileURLWithPath: CommandLine.arguments[1])
let icnsURL = URL(fileURLWithPath: CommandLine.arguments[2])

func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
}

func superellipse(in rect: CGRect, exponent: CGFloat = 4.0) -> CGPath {
    let path = CGMutablePath()
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let halfWidth = rect.width / 2
    let halfHeight = rect.height / 2
    let steps = 512

    for index in 0...steps {
        let angle = CGFloat(index) / CGFloat(steps) * 2 * .pi
        let cosine = cos(angle)
        let sine = sin(angle)
        let x = center.x + halfWidth * (cosine < 0 ? -1 : 1) * pow(abs(cosine), 2 / exponent)
        let y = center.y + halfHeight * (sine < 0 ? -1 : 1) * pow(abs(sine), 2 / exponent)
        if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
    }
    path.closeSubpath()
    return path
}

func renderIcon(size: Int) throws -> Data {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: size,
            pixelsHigh: size,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let graphics = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
        throw NSError(
            domain: "AirCillerIcon", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se pudo crear el lienzo."])
    }

    bitmap.size = NSSize(width: size, height: size)
    let scale = CGFloat(size) / 1024
    let context = graphics.cgContext
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphics
    context.clear(CGRect(x: 0, y: 0, width: size, height: size))
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    // La silueta ocupa la misma zona útil que los iconos nativos de macOS:
    // deja aire transparente alrededor y conserva una curva continua.
    let iconRect = CGRect(x: 96 * scale, y: 104 * scale, width: 832 * scale, height: 832 * scale)
    let mask = superellipse(in: iconRect)

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -14 * scale),
        blur: 24 * scale,
        color: NSColor(calibratedWhite: 0, alpha: 0.24).cgColor
    )
    context.addPath(mask)
    context.setFillColor(NSColor(calibratedWhite: 0.1, alpha: 0.9).cgColor)
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(mask)
    context.clip()

    let background = NSGradient(
        colorsAndLocations: (NSColor(calibratedRed: 1.000, green: 0.890, blue: 0.070, alpha: 1), 0.0),
        (NSColor(calibratedRed: 1.000, green: 0.755, blue: 0.000, alpha: 1), 0.58),
        (NSColor(calibratedRed: 1.000, green: 0.650, blue: 0.000, alpha: 1), 1.0)
    )!
    background.draw(in: iconRect, angle: -90)

    let sheen = NSGradient(colors: [
        NSColor(calibratedWhite: 1, alpha: 0.38),
        NSColor(calibratedWhite: 1, alpha: 0),
    ])!
    sheen.draw(
        fromCenter: CGPoint(x: 300 * scale, y: 845 * scale),
        radius: 12 * scale,
        toCenter: CGPoint(x: 420 * scale, y: 690 * scale),
        radius: 520 * scale,
        options: [.drawsBeforeStartingLocation]
    )

    context.addPath(mask)
    context.setStrokeColor(NSColor(calibratedWhite: 1, alpha: 0.27).cgColor)
    context.setLineWidth(3 * scale)
    context.strokePath()

    // Marca propia: una pantalla y un haz abierto. Conserva la lectura de
    // “enviar a la pantalla” sin reutilizar un SF Symbol como logotipo.
    context.translateBy(x: 96 * scale, y: 104 * scale)
    context.scaleBy(x: 0.8125 * scale, y: 0.8125 * scale)

    let screen = CGMutablePath()
    screen.addRoundedRect(
        in: CGRect(x: 216, y: 410, width: 592, height: 350),
        cornerWidth: 92,
        cornerHeight: 92
    )
    screen.addRoundedRect(
        in: CGRect(x: 292, y: 482, width: 440, height: 206),
        cornerWidth: 34,
        cornerHeight: 34
    )

    let beam = CGMutablePath()
    beam.move(to: CGPoint(x: 376, y: 236))
    beam.addLine(to: CGPoint(x: 512, y: 526))
    beam.addLine(to: CGPoint(x: 648, y: 236))

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -9),
        blur: 18,
        color: NSColor(calibratedWhite: 0, alpha: 0.22).cgColor
    )
    context.addPath(screen)
    context.setFillColor(NSColor.white.cgColor)
    context.drawPath(using: .eoFill)
    context.addPath(beam)
    context.setStrokeColor(NSColor.white.cgColor)
    context.setLineWidth(76)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
    context.restoreGState()

    context.saveGState()
    context.addPath(screen)
    context.clip(using: .evenOdd)
    let glyphGradient = NSGradient(colors: [
        NSColor(calibratedWhite: 1, alpha: 1),
        NSColor(calibratedWhite: 0.94, alpha: 1),
    ])!
    glyphGradient.draw(in: CGRect(x: 190, y: 390, width: 644, height: 390), angle: -90)
    context.restoreGState()

    context.addPath(beam)
    context.setStrokeColor(NSColor(calibratedWhite: 0.98, alpha: 1).cgColor)
    context.setLineWidth(76)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.strokePath()
    context.restoreGState()

    graphics.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [.compressionFactor: 0.92]) else {
        throw NSError(
            domain: "AirCillerIcon", code: 2, userInfo: [NSLocalizedDescriptionKey: "No se pudo codificar el PNG."])
    }
    return png
}

do {
    let master = try renderIcon(size: 1024)
    try master.write(to: pngURL, options: .atomic)

    // ICNS admite una representación específica por escala. No dependemos de
    // iconutil, que en macOS 27 no recompone ni siquiera iconos del sistema.
    let representations: [(String, Int)] = [
        ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024),
        ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512),
    ]
    var elements = Data()
    for (type, pixels) in representations {
        let image = try renderIcon(size: pixels)
        elements.append(type.data(using: .ascii)!)
        appendUInt32(UInt32(image.count + 8), to: &elements)
        elements.append(image)
    }

    var icns = Data("icns".utf8)
    appendUInt32(UInt32(elements.count + 8), to: &icns)
    icns.append(elements)
    try icns.write(to: icnsURL, options: .atomic)
} catch {
    fputs("No se pudo generar el icono: \(error.localizedDescription)\n", stderr)
    exit(1)
}
