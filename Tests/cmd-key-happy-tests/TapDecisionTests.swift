import Carbon.HIToolbox
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

    /// kVK_ANSI_F, a key that is not a modifier. The keycode only
    /// matters for flagsChanged, where it says which modifier key the
    /// event is about.
    private let someKey = CGKeyCode(kVK_ANSI_F)

    private func action(_ type: CGEventType,
                        _ flags: CGEventFlags,
                        keyCode: CGKeyCode? = nil,
                        target: pid_t? = nil) -> TapAction {
        tapAction(for: type,
                  flags: flags,
                  keyCode: keyCode ?? someKey,
                  targetPID: target ?? tapped,
                  tappedPID: tapped)
    }

    func testCommandAloneBecomesOption() {
        XCTAssertEqual(action(.keyDown, [.maskCommand]), .swap([.maskAlternate]))
    }

    func testOptionAloneBecomesCommand() {
        XCTAssertEqual(action(.keyDown, [.maskAlternate]), .swap([.maskCommand]))
    }

    /// Exchanging the two when both are held maps the pair onto
    /// itself, so the event is delivered as it arrived. Nothing
    /// declines to swap here; there is nothing left to alter.
    func testHoldingBothIsUnchangedByTheExchange() {
        XCTAssertEqual(action(.keyDown, [.maskCommand, .maskAlternate]), .passThrough)
    }

    func testNeitherHeldPassesThrough() {
        XCTAssertEqual(action(.keyDown, []), .passThrough)
    }

    func testAnotherProcessPassesThrough() {
        XCTAssertEqual(action(.keyDown, [.maskCommand], target: other), .passThrough)
    }

    func testAModifierWeDoNotSwapPassesThrough() {
        let leftShift = CGEventFlags(rawValue: UInt64(NX_DEVICELSHIFTKEYMASK))
        XCTAssertEqual(action(.flagsChanged, [.maskShift, leftShift], keyCode: CGKeyCode(kVK_Shift)),
                       .passThrough)
    }

    /// A modifier we do not swap, pressed while command is held. Its
    /// flags carry the whole modifier state, command included, so
    /// passing them through tells the application command is held
    /// after all -- moments after it was told option was. The keycode
    /// is not ours to move; the flags are.
    func testAModifierWeDoNotSwapStillReportsTheSwappedState() {
        let rightControl = CGEventFlags(rawValue: UInt64(NX_DEVICERCTLKEYMASK))
        let leftCommand = CGEventFlags(rawValue: UInt64(NX_DEVICELCMDKEYMASK))
        let leftOption = CGEventFlags(rawValue: UInt64(NX_DEVICELALTKEYMASK))
        XCTAssertEqual(
          action(.flagsChanged,
                 [.maskControl, rightControl, .maskCommand, leftCommand],
                 keyCode: CGKeyCode(kVK_RightControl)),
          .swap([.maskControl, rightControl, .maskAlternate, leftOption]))
    }

    /// Holding both on opposite sides. Nothing swaps for the generic
    /// bits -- both stay held -- but the sides still have to follow
    /// the story the modifier events told.
    func testHoldingBothOnOppositeSidesStillSwapsTheSides() {
        let leftCommand = CGEventFlags(rawValue: UInt64(NX_DEVICELCMDKEYMASK))
        let rightOption = CGEventFlags(rawValue: UInt64(NX_DEVICERALTKEYMASK))
        let leftOption = CGEventFlags(rawValue: UInt64(NX_DEVICELALTKEYMASK))
        let rightCommand = CGEventFlags(rawValue: UInt64(NX_DEVICERCMDKEYMASK))
        XCTAssertEqual(
          action(.keyDown, [.maskCommand, leftCommand, .maskAlternate, rightOption]),
          .swap([.maskCommand, .maskAlternate, leftOption, rightCommand]))
    }

    func testAnEventTypeWeDoNotHandlePassesThrough() {
        XCTAssertEqual(action(.scrollWheel, [.maskCommand]), .passThrough)
    }

    // MARK: - the release half of a chord

    /// Only keyDown was transformed, so holding command and tapping a
    /// key delivered the press as option and the release as command.
    /// Applications that track releases -- kitty's keyboard protocol,
    /// Ghostty -- were told a key went down under one modifier and came
    /// up under another.
    func testKeyUpIsSwappedLikeKeyDown() {
        XCTAssertEqual(action(.keyUp, [.maskCommand]), .swap([.maskAlternate]))
    }

    func testKeyUpHoldingBothPassesThrough() {
        XCTAssertEqual(action(.keyUp, [.maskCommand, .maskAlternate]), .passThrough)
    }

    func testKeyUpFromAnotherProcessPassesThrough() {
        XCTAssertEqual(action(.keyUp, [.maskCommand], target: other), .passThrough)
    }

    // MARK: - the modifier key itself

    /// The event that says a modifier went down or up carries the
    /// physical key in its keycode, and applications use it to decide
    /// which modifier changed. Rewriting the flags alone would tell
    /// them the command key was pressed with the command bit clear,
    /// which reads as a release.
    func testCommandGoingDownIsDeliveredAsOptionGoingDown() {
        let leftCommand = CGEventFlags(rawValue: UInt64(NX_DEVICELCMDKEYMASK))
        let leftOption = CGEventFlags(rawValue: UInt64(NX_DEVICELALTKEYMASK))
        XCTAssertEqual(action(.flagsChanged, [.maskCommand, leftCommand], keyCode: CGKeyCode(kVK_Command)),
                       .swapModifierKey(flags: [.maskAlternate, leftOption], keyCode: CGKeyCode(kVK_Option)))
    }

    func testRightOptionGoingDownIsDeliveredAsRightCommandGoingDown() {
        let rightOption = CGEventFlags(rawValue: UInt64(NX_DEVICERALTKEYMASK))
        let rightCommand = CGEventFlags(rawValue: UInt64(NX_DEVICERCMDKEYMASK))
        XCTAssertEqual(action(.flagsChanged, [.maskAlternate, rightOption], keyCode: CGKeyCode(kVK_RightOption)),
                       .swapModifierKey(flags: [.maskCommand, rightCommand], keyCode: CGKeyCode(kVK_RightCommand)))
    }

    /// A release carries no modifier bits at all, so there is nothing
    /// in the flags to swap and only the keycode says which key it
    /// was. Passing it through unchanged would report the release of a
    /// key the application never saw pressed, and leave it believing
    /// option was still held.
    func testCommandGoingUpIsDeliveredAsOptionGoingUp() {
        XCTAssertEqual(action(.flagsChanged, [], keyCode: CGKeyCode(kVK_Command)),
                       .swapModifierKey(flags: [], keyCode: CGKeyCode(kVK_Option)))
    }

    /// Holding both is left alone for a key press, but the modifier
    /// events themselves are always relabelled: the application has
    /// already been told option went down, and it has to be told
    /// option came up.
    func testTheSecondModifierIsRelabelledWhileTheFirstIsHeld() {
        let leftCommand = CGEventFlags(rawValue: UInt64(NX_DEVICELCMDKEYMASK))
        let leftOption = CGEventFlags(rawValue: UInt64(NX_DEVICELALTKEYMASK))
        XCTAssertEqual(
          action(.flagsChanged,
                 [.maskCommand, leftCommand, .maskAlternate, leftOption],
                 keyCode: CGKeyCode(kVK_Option)),
          .swapModifierKey(flags: [.maskCommand, leftCommand, .maskAlternate, leftOption],
                           keyCode: CGKeyCode(kVK_Command)))
    }

    func testAModifierEventFromAnotherProcessPassesThrough() {
        XCTAssertEqual(action(.flagsChanged, [.maskCommand], keyCode: CGKeyCode(kVK_Command), target: other),
                       .passThrough)
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
