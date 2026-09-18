import CoreGraphics
import IOKit
import XCTest

@testable import cmd_key_happy

/// What the callback should do with one event, as a table. A chord
/// holding both command and option is delivered unchanged, a modifier
/// held on one side keeps that side, and a disabled tap asks to be
/// turned back on rather than being discarded with everything that is
/// not a key press.
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

    // MARK: - which side the modifier is on

    /// The generic bit says a modifier is held; the device-dependent
    /// bits say which of the two physical keys it was. Applications
    /// read them -- Ghostty decides whether to treat option as alt by
    /// side -- so swapping the generic bit alone hands them an event
    /// claiming option while the side bits still say command.
    private let leftCommand = CGEventFlags(rawValue: UInt64(NX_DEVICELCMDKEYMASK))
    private let rightCommand = CGEventFlags(rawValue: UInt64(NX_DEVICERCMDKEYMASK))
    private let leftOption = CGEventFlags(rawValue: UInt64(NX_DEVICELALTKEYMASK))
    private let rightOption = CGEventFlags(rawValue: UInt64(NX_DEVICERALTKEYMASK))

    func testRightCommandBecomesRightOption() {
        XCTAssertEqual(action(.keyDown, [.maskCommand, rightCommand]),
                       .swap([.maskAlternate, rightOption]))
    }

    func testLeftCommandBecomesLeftOption() {
        XCTAssertEqual(action(.keyDown, [.maskCommand, leftCommand]),
                       .swap([.maskAlternate, leftOption]))
    }

    func testRightOptionBecomesRightCommand() {
        XCTAssertEqual(action(.keyDown, [.maskAlternate, rightOption]),
                       .swap([.maskCommand, rightCommand]))
    }

    func testLeftOptionBecomesLeftCommand() {
        XCTAssertEqual(action(.keyDown, [.maskAlternate, leftOption]),
                       .swap([.maskCommand, leftCommand]))
    }

    /// Both physical keys of the same modifier held at once.
    func testBothCommandKeysBecomeBothOptionKeys() {
        XCTAssertEqual(action(.keyDown, [.maskCommand, leftCommand, rightCommand]),
                       .swap([.maskAlternate, leftOption, rightOption]))
    }

    /// Modifiers that are not being swapped keep their own side bits.
    func testTheSideBitsOfOtherModifiersAreUntouched() {
        let leftShift = CGEventFlags(rawValue: UInt64(NX_DEVICELSHIFTKEYMASK))
        XCTAssertEqual(action(.keyDown, [.maskCommand, rightCommand, .maskShift, leftShift]),
                       .swap([.maskAlternate, rightOption, .maskShift, leftShift]))
    }
}
