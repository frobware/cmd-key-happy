import Carbon.HIToolbox
import CoreGraphics
import IOKit
import XCTest

@testable import cmd_key_happy

/// The trace line: what arrived and what was delivered. Without it,
/// seeing what the tap did to a keystroke means attaching a debugger
/// to the application receiving it.
final class TapTraceTests: XCTestCase {
    private let leftCommand = CGEventFlags(rawValue: UInt64(NX_DEVICELCMDKEYMASK))
    private let leftOption = CGEventFlags(rawValue: UInt64(NX_DEVICELALTKEYMASK))

    /// The columns are padded, so compare on the words rather than on
    /// the exact run of spaces between them.
    private func words(_ line: String?) -> String? {
        line?.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }

    private func line(_ kind: KeyboardKind,
                      _ flags: CGEventFlags,
                      keyCode: CGKeyCode,
                      action: TapAction) -> String? {
        tapTraceLine(app: "Ghostty", pid: 1234,
                     event: .keyboard(kind: kind, flags: flags, keyCode: keyCode),
                     action: action)
    }

    func testASwapShowsBothSides() {
        let trace = line(.keyDown, [.maskCommand, leftCommand],
                         keyCode: CGKeyCode(kVK_ANSI_F),
                         action: .swap([.maskAlternate, leftOption]))
        XCTAssertEqual(words(trace),
                       "Ghostty[1234] event=keyDown key=3"
                         + " modifiers.in=cmd(L) modifiers.out=opt(L)")
    }

    /// A pass-through that had a command or option in it is worth a
    /// line: the question being asked is why that chord was not
    /// swapped. It is marked == rather than ->, so the eye can skip
    /// what did not change.
    func testAPassThroughCarryingCommandIsTracedAsUnchanged() {
        let trace = line(.keyDown, [.maskCommand, .maskAlternate],
                         keyCode: CGKeyCode(kVK_ANSI_F),
                         action: .passThrough)
        XCTAssertEqual(words(trace),
                       "Ghostty[1234] event=keyDown key=3 modifiers=cmd,opt")
    }

    /// Everything else that passes through is noise. A tapped
    /// application receives every keystroke typed into it, and a line
    /// each for the ones we never had any intention of touching buries
    /// the ones we did.
    func testAKeystrokeWeHaveNoInterestInIsNotTraced() {
        XCTAssertNil(line(.keyDown, [], keyCode: CGKeyCode(kVK_ANSI_F), action: .passThrough))
    }

    func testAModifierWeNeverSwapIsNotTraced() {
        let rightShift = CGEventFlags(rawValue: UInt64(NX_DEVICERSHIFTKEYMASK))
        XCTAssertNil(line(.flagsChanged, [.maskShift, rightShift],
                          keyCode: CGKeyCode(kVK_RightShift), action: .passThrough))
    }

    /// Shift while command is held is traced, because the command bit
    /// riding along in it does change.
    func testAModifierWeNeverSwapIsTracedWhileCommandIsHeld() {
        let rightShift = CGEventFlags(rawValue: UInt64(NX_DEVICERSHIFTKEYMASK))
        let trace = line(.flagsChanged, [.maskShift, rightShift, .maskCommand, leftCommand],
                         keyCode: CGKeyCode(kVK_RightShift),
                         action: .swap([.maskShift, rightShift, .maskAlternate, leftOption]))
        XCTAssertEqual(words(trace),
                       "Ghostty[1234] event=flagsChanged key=R-shift"
                         + " modifiers.in=cmd(L),shift(R)"
                         + " modifiers.out=opt(L),shift(R)")
    }

    func testAModifierKeyShowsTheKeycodeChanging() {
        let trace = line(.flagsChanged, [.maskCommand, leftCommand],
                         keyCode: CGKeyCode(kVK_Command),
                         action: .swapModifierKey(flags: [.maskAlternate, leftOption],
                                                  keyCode: CGKeyCode(kVK_Option)))
        XCTAssertEqual(words(trace),
                       "Ghostty[1234] event=flagsChanged key.in=L-cmd key.out=L-opt"
                         + " modifiers.in=cmd(L) modifiers.out=opt(L)")
    }

    /// A modifier release carries no bits at all, so the key is the
    /// only thing in the line saying what happened.
    func testNoModifiersSaysSo() {
        let trace = line(.flagsChanged, [],
                         keyCode: CGKeyCode(kVK_Command),
                         action: .swapModifierKey(flags: [], keyCode: CGKeyCode(kVK_Option)))
        XCTAssertEqual(words(trace),
                       "Ghostty[1234] event=flagsChanged key.in=L-cmd key.out=L-opt"
                         + " modifiers=none")
    }

    /// The columns are padded to line up, and padding that truncates
    /// would drop exactly the unusual combination worth seeing.
    func testALongModifierSetIsNotTruncated() throws {
        let everything: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift,
                                        .maskControl, .maskSecondaryFn, leftCommand, leftOption]
        let trace = try XCTUnwrap(line(.keyDown, everything,
                                       keyCode: CGKeyCode(kVK_ANSI_F),
                                       action: .passThrough))
        for name in ["cmd(L)", "opt(L)", "shift", "ctrl", "fn"] {
            XCTAssertTrue(trace.contains(name), "\(name) missing from: \(trace)")
        }
    }

    /// A side bit with no modifier held is not a state a keyboard can
    /// produce, so it has to be visible rather than rendered away.
    func testASideBitWithoutItsModifierIsShownOnItsOwn() {
        let rightCommand = CGEventFlags(rawValue: UInt64(NX_DEVICERCMDKEYMASK))
        let trace = line(.keyDown, [.maskAlternate, rightCommand],
                         keyCode: CGKeyCode(kVK_ANSI_F), action: .passThrough)
        XCTAssertEqual(words(trace),
                       "Ghostty[1234] event=keyDown key=3 modifiers=(R-cmd),opt")
    }

    /// A disabled tap is already reported at error level, and saying
    /// it twice would make a rare event look like two.
    func testADisabledTapIsNotTracedHere() {
        XCTAssertNil(tapTraceLine(app: "Ghostty", pid: 1234,
                                  event: .disabled(.timeout), action: .reEnable(.timeout)))
    }
}
