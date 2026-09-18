import AppKit

/// The application icon: a face built from the command key's parts.
///
/// The two ring eyes take the clover loops' proportions, the hole
/// about half the outer radius. The nose is the wedge the Finder icon
/// makes of its profile, pointing left with the underside notched
/// back. Drawn rather than stored, so the icon has one source and
/// `make` can regenerate it at any size.
///
/// Every measurement is a fraction of the canvas, so the drawing is
/// resolution independent.
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
    ctx.translateBy(x: s / 2, y: s / 2)

    // Each eye is a clover leaf, outlined the way the loops of the
    // command glyph are, and drawn to a point on the side facing the
    // nose.
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(Icon.eyeStroke * s)
    ctx.setLineJoin(.miter)
    for side in [CGFloat(-1), 1] {
        ctx.addPath(leafPath(side: side, size: s))
    }
    ctx.strokePath()

    ctx.addPath(nosePath(size: s))
    ctx.setFillColor(ink)
    ctx.fillPath()

    ctx.addPath(smilePath(size: s))
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(Icon.smileStroke * s)
    ctx.setLineCap(.round)
    ctx.strokePath()

    return ctx.makeImage()
}

/// The face, as fractions of the canvas, measured from its centre.
///
/// Everything derives from `faceHalf`, so the face keeps its shape and
/// its square footprint whatever size it is drawn at, and the border
/// round it is the same on all four sides. The eyes set both the width
/// and the top of that square; the smile sets the bottom.
enum Icon {
    /// The plate's half-height, from the same inset the drawing uses.
    static let plateHalf: CGFloat = 0.5 - 0.098

    /// Half the width of the square the face occupies. The border is
    /// whatever is left: `plateHalf - faceHalf`, on every side.
    static let faceHalf: CGFloat = 0.3160

    static var eyeRadius: CGFloat { 0.385 * faceHalf }
    static var eyeStroke: CGFloat { 0.160 * faceHalf }
    /// The eyes touch the square at the top and at both sides, which
    /// is what makes those three borders equal.
    static var eyeX: CGFloat { faceHalf - (eyeRadius + eyeStroke / 2) }
    static var eyeY: CGFloat { eyeX }

    /// How far the leaf's point reaches from the eye's centre, as a
    /// multiple of its radius. This fixes the leaf's shape; only the
    /// direction follows the nose, so moving the nose turns the
    /// leaves rather than stretching them.
    static let eyeCuspReach: CGFloat = 1.50

    /// The bridge starts below the eyes, so the leaves' points aim
    /// down and inward at it.
    static let noseApexX: CGFloat = 0
    static var noseApexY: CGFloat { 0.05 * faceHalf }
    static var noseTipX: CGFloat { -0.250 * faceHalf }
    static var noseRightX: CGFloat { 0.185 * faceHalf }
    static var noseBottomY: CGFloat { -0.200 * faceHalf }

    static var smileWidth: CGFloat { 1.640 * faceHalf }
    static var smileStroke: CGFloat { 0.160 * faceHalf }
    static let smileSweep: CGFloat = 0.40
    /// The smile touches the bottom of the square, stroke included.
    static var smileLowest: CGFloat { -faceHalf + smileStroke / 2 }

    /// Where the arc starts, and the radius that gives it the stated
    /// width. The drawing and the geometry tests share these rather
    /// than each deriving them.
    static var smileStartAngle: CGFloat { .pi * (1.5 - smileSweep) }
    static var smileRadius: CGFloat { smileWidth / (2 * abs(cos(smileStartAngle))) }
    static var smileCentreY: CGFloat { smileLowest + smileRadius }
    /// The height of the smile's two ends, which is the highest the
    /// mouth reaches and so what the nose has to stay clear of.
    static var smileEndY: CGFloat { smileCentreY + smileRadius * sin(smileStartAngle) }

    /// From an eye's centre to the top of the nose, which is the line
    /// the leaf's point is drawn along.
    static var eyeToNoseApex: CGFloat {
        let dx = eyeX - abs(noseApexX), dy = eyeY - noseApexY
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// One eye: a clover leaf, a circle drawn out to a point.
///
/// The point aims at the top of the nose, so the two leaves converge
/// on it and lead into the wedge. The straight edges are tangents, so
/// they meet the circle without a corner. `side` is -1 for the left
/// eye and 1 for the right.
private func leafPath(side: CGFloat, size s: CGFloat) -> CGPath {
    let centre = CGPoint(x: side * Icon.eyeX * s, y: Icon.eyeY * s)
    let apex = CGPoint(x: Icon.noseApexX * s, y: Icon.noseApexY * s)
    let outer = Icon.eyeRadius * s
    let towardNose = atan2(apex.y - centre.y, apex.x - centre.x)
    let reach = Icon.eyeRadius * Icon.eyeCuspReach * s
    let half = acos(outer / reach)
    let tip = CGPoint(x: centre.x + reach * cos(towardNose),
                      y: centre.y + reach * sin(towardNose))

    let path = CGMutablePath()
    path.addArc(center: centre, radius: outer,
                startAngle: towardNose + half,
                endAngle: towardNose - half,
                clockwise: false)
    path.addLine(to: tip)
    path.closeSubpath()
    return path
}

/// The Finder's nose: the bridge runs down from between the eyes to a
/// point at the left, then cuts back sharply underneath.
private func nosePath(size s: CGFloat) -> CGPath {
    let apex = CGPoint(x: Icon.noseApexX * s, y: Icon.noseApexY * s)
    let bottom = Icon.noseBottomY * s
    let tip = CGPoint(x: Icon.noseTipX * s, y: bottom)
    let width = (Icon.noseRightX - Icon.noseTipX) * s
    let path = CGMutablePath()
    path.move(to: apex)
    path.addLine(to: CGPoint(x: tip.x, y: tip.y + width * 0.07))
    path.addQuadCurve(to: CGPoint(x: tip.x + width * 0.20, y: bottom),
                      control: CGPoint(x: tip.x, y: bottom))
    path.addLine(to: CGPoint(x: Icon.noseRightX * s, y: bottom + width * 0.05))
    path.closeSubpath()
    return path
}

/// The smile a child draws: wide, deep, and round at both ends.
///
/// The arc is described by where its lowest point sits and how wide it
/// is end to end, which is what the eye judges; the radius follows.
private func smilePath(size s: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.addArc(center: CGPoint(x: 0, y: Icon.smileCentreY * s),
                radius: Icon.smileRadius * s,
                startAngle: Icon.smileStartAngle,
                endAngle: .pi * (1.5 + Icon.smileSweep),
                clockwise: false)
    return path
}

func writePNG(_ image: CGImage, to url: URL) throws {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
    try data.write(to: url)
}
