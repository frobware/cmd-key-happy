import CoreGraphics
import XCTest

@testable import cmd_key_happy

/// The swap is a symmetric difference of the command and option bits,
/// which is only valid when exactly one of them is held. Holding both
/// once passed the guard, and XOR then cleared both, delivering a
/// cmd+opt chord as a bare keypress. The both-keys row below is that
/// defect; the two disabled rows are the notification that used to be
/// discarded along with everything that is not a key press.
final class TapDecisionTests: XCTestCase {
    private let tapped: pid_t = 501
    private let other: pid_t = 999

    private func action(_ type: CGEventType,
                        _ flags: CGEventFlags,
                        target: pid_t? = nil) -> TapAction {
        tapAction(for: type, flags: flags, targetPID: target ?? tapped, tappedPID: tapped)
    }

    func testCommandAloneBecomesOption() {
        XCTAssertEqual(action(.keyDown, [.maskCommand]), .swap([.maskAlternate]))
    }

    func testOptionAloneBecomesCommand() {
        XCTAssertEqual(action(.keyDown, [.maskAlternate]), .swap([.maskCommand]))
    }

    func testBothHeldPassesThrough() {
        XCTAssertEqual(action(.keyDown, [.maskCommand, .maskAlternate]), .passThrough)
    }

    func testNeitherHeldPassesThrough() {
        XCTAssertEqual(action(.keyDown, []), .passThrough)
    }

    func testAnotherProcessPassesThrough() {
        XCTAssertEqual(action(.keyDown, [.maskCommand], target: other), .passThrough)
    }

    func testNonKeyDownPassesThrough() {
        XCTAssertEqual(action(.flagsChanged, [.maskCommand]), .passThrough)
    }

    func testDisabledByTimeoutIsReEnabled() {
        XCTAssertEqual(action(.tapDisabledByTimeout, []), .reEnable(.timeout))
    }

    func testDisabledByUserInputIsReEnabled() {
        XCTAssertEqual(action(.tapDisabledByUserInput, []), .reEnable(.userInput))
    }

    /// A disabled tap must be reported whatever else is set: the
    /// notification carries no meaningful flags or target, and an
    /// earlier version discarded it by checking for .keyDown first.
    func testDisabledWinsOverEveryOtherCondition() {
        XCTAssertEqual(action(.tapDisabledByTimeout, [.maskCommand], target: other),
                       .reEnable(.timeout))
    }

    /// Unrelated modifiers ride along untouched.
    func testOtherModifiersArePreserved() {
        XCTAssertEqual(action(.keyDown, [.maskCommand, .maskShift, .maskControl]),
                       .swap([.maskAlternate, .maskShift, .maskControl]))
    }
}
