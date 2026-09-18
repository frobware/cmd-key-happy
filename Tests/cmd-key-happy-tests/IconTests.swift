import CoreGraphics
import XCTest

@testable import cmd_key_happy

/// The icon's geometry.
///
/// How it looks is a matter for the eye, but the features have to keep
/// out of each other's way, and that is arithmetic: a constant nudged
/// by a few thousandths puts the nose through an eye or the mouth off
/// the plate, and nothing else would report it.
final class IconTests: XCTestCase {
    /// The round part of a leaf, before its point, stroke included.
    private var eyeOuter: CGFloat { Icon.eyeRadius + Icon.eyeStroke / 2 }

    /// How far a leaf's point reaches from the eye's centre.
    private var leafReach: CGFloat { Icon.eyeRadius * Icon.eyeCuspReach }

    private func distanceFromEyeCentre(toX x: CGFloat, y: CGFloat, side: CGFloat) -> CGFloat {
        let dx = x - side * Icon.eyeX, dy = y - Icon.eyeY
        return (dx * dx + dy * dy).squareRoot()
    }

    func testTheNoseApexClearsBothEyes() {
        for side in [CGFloat(-1), 1] {
            let d = distanceFromEyeCentre(toX: Icon.noseApexX, y: Icon.noseApexY, side: side)
            XCTAssertGreaterThan(d, eyeOuter,
                                 "the bridge starts inside the eye on side \(side)")
        }
    }

    /// The bridge runs down between the eyes, so it has to fit the
    /// channel their inner edges leave.
    func testTheNoseApexSitsInTheChannelBetweenTheEyes() {
        XCTAssertLessThan(abs(Icon.noseApexX), Icon.eyeX - eyeOuter)
    }

    /// The ends of the arc are the highest the mouth reaches.
    func testTheNoseStopsAboveTheSmile() {
        XCTAssertGreaterThan(Icon.noseBottomY, Icon.smileEndY)
    }

    func testTheNoseWidensDownwards() {
        XCTAssertLessThan(Icon.noseTipX, Icon.noseApexX)
        XCTAssertGreaterThan(Icon.noseRightX, Icon.noseApexX)
        XCTAssertLessThan(Icon.noseBottomY, Icon.noseApexY)
    }

    /// The face sits in the plate with a border round it, and the
    /// same border above and below. The eyes are the highest thing
    /// drawn and the smile the lowest, so those two set it.
    func testTheBorderAboveAndBelowMatches() {
        let top = Icon.plateHalf - (Icon.eyeY + eyeOuter)
        let bottom = Icon.plateHalf + (Icon.smileLowest - Icon.smileStroke / 2)
        XCTAssertEqual(top, bottom, accuracy: 0.005,
                       "top border \(top) against bottom \(bottom)")
        XCTAssertGreaterThan(top, 0.06, "no room round the face")
    }

    /// The plate is a squircle, so its corners are cut; the sides may
    /// be roomier than the top and bottom but never tighter.
    func testTheSidesAreNoTighterThanTheTop() {
        let top = Icon.plateHalf - (Icon.eyeY + eyeOuter)
        let side = Icon.plateHalf - (Icon.eyeX + eyeOuter)
        XCTAssertGreaterThanOrEqual(side, top)
    }

    func testTheSmileStaysOnThePlate() {
        XCTAssertGreaterThan(Icon.smileLowest - Icon.smileStroke / 2, -Icon.plateHalf)
    }

    func testTheEyesStayOnThePlate() {
        XCTAssertLessThan(Icon.eyeY + eyeOuter, Icon.plateHalf)
        XCTAssertLessThan(Icon.eyeX + eyeOuter, Icon.plateHalf)
    }

    /// The tangent construction needs the point to reach beyond the
    /// circle; at or inside it there is no leaf, and acos would give
    /// nothing to draw.
    func testTheLeafPointReachesBeyondItsCircle() {
        XCTAssertGreaterThan(leafReach, Icon.eyeRadius)
    }

    /// The points lead into the nose rather than touching it.
    func testTheLeafPointsStopShortOfTheNose() {
        XCTAssertLessThan(leafReach, Icon.eyeToNoseApex)
    }

    /// Renders at the size asked for, and carries both ink and ground:
    /// a path that came out empty would still be a valid image.
    func testItRendersSomething() throws {
        let size = 128
        let image = try XCTUnwrap(drawCmdKeyHappyIcon(size: size))
        XCTAssertEqual(image.width, size)
        XCTAssertEqual(image.height, size)

        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let ctx = try XCTUnwrap(CGContext(data: &pixels, width: size, height: size,
                                          bitsPerComponent: 8, bytesPerRow: size * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        var light = 0, dark = 0
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i + 3] > 128 {
            if pixels[i] > 200 { light += 1 } else { dark += 1 }
        }
        XCTAssertGreaterThan(light, 0, "no ink")
        XCTAssertGreaterThan(dark, 0, "no ground")
    }
}
