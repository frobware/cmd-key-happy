import AppKit
import CoreText

/// The application icon: the command glyph wearing a face.
///
/// U+2318 already has two loops where eyes belong, so the face is
/// made by inking the negative space rather than by adding to the
/// mark: pupils inside the upper loops, and a smile struck across the
/// lower interior. Drawn rather than stored, so the icon has one
/// source and `make` can regenerate it at any size.
func drawCmdKeyHappyIcon(size: Int) -> CGImage? {
    let s = CGFloat(size)
    guard let ctx = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // The macOS icon grid: the squircle fills about 80% of the canvas,
    // with continuous corners near 22.5% of its width.
    let plate = CGRect(x: 0, y: 0, width: s, height: s).insetBy(dx: 0.098 * s, dy: 0.098 * s)
    let corner = plate.width * 0.225
    ctx.addPath(CGPath(roundedRect: plate, cornerWidth: corner, cornerHeight: corner, transform: nil))
    ctx.clip()

    let ground = CGColor(srgbRed: 0.11, green: 0.13, blue: 0.19, alpha: 1)
    let sky = CGGradient(
      colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
      colors: [CGColor(srgbRed: 0.26, green: 0.30, blue: 0.40, alpha: 1), ground] as CFArray,
      locations: [0, 1])!
    ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

    let ink = CGColor(srgbRed: 0.98, green: 0.98, blue: 1.0, alpha: 1)
    ctx.saveGState()
    ctx.translateBy(x: s / 2, y: s / 2)
    ctx.addPath(commandGlyphPath(size: 0.68 * s))
    ctx.setFillColor(ink)
    ctx.fillPath()
    ctx.restoreGState()

    // Pupils sit in the upper loops, which the glyph already provides.
    ctx.setFillColor(ground)
    for dx in [-0.115, 0.115] as [CGFloat] {
        ctx.fillEllipse(in: CGRect(x: s / 2 + dx * s - 0.028 * s,
                                   y: s / 2 + 0.115 * s - 0.028 * s,
                                   width: 0.056 * s, height: 0.056 * s))
    }

    // The smile is struck in the ground colour so it cuts through the
    // mark; drawn in the ink colour it would vanish into it.
    let smile = CGMutablePath()
    smile.addArc(center: CGPoint(x: s / 2, y: s / 2 + 0.02 * s),
                 radius: 0.115 * s,
                 startAngle: .pi * 1.12, endAngle: .pi * 1.88,
                 clockwise: false)
    ctx.addPath(smile)
    ctx.setStrokeColor(ground)
    ctx.setLineWidth(0.032 * s)
    ctx.setLineCap(.round)
    ctx.strokePath()

    return ctx.makeImage()
}

/// U+2318 as a path, centred on the origin. Apple Symbols carries the
/// glyph; Helvetica and SF Pro do not, and fall back to .notdef.
private func commandGlyphPath(size: CGFloat) -> CGPath {
    let font = CTFontCreateWithName("Apple Symbols" as CFString, size, nil)
    var characters: [UniChar] = Array("\u{2318}".utf16)
    var glyphs = [CGGlyph](repeating: 0, count: characters.count)
    CTFontGetGlyphsForCharacters(font, &characters, &glyphs, characters.count)
    guard let path = CTFontCreatePathForGlyph(font, glyphs[0], nil) else {
        return CGMutablePath()
    }
    let bounds = path.boundingBox
    var centre = CGAffineTransform(translationX: -bounds.midX, y: -bounds.midY)
    return path.copy(using: &centre) ?? path
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try data.write(to: url)
}
