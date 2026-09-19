import Carbon.HIToolbox
import CoreGraphics
import IOKit

/// Why macOS switched an active tap off.
enum DisableReason: Equatable {
    case timeout
    case userInput

    var description: String {
        switch self {
        case .timeout: return "timeout"
        case .userInput: return "user input"
        }
    }
}

/// The keyboard events a tap asks for.
enum KeyboardKind: Equatable {
    case keyDown
    case keyUp
    case flagsChanged
}

/// One event, as the decision sees it.
///
/// A disable notification carries no keyboard fields, and no case
/// here can hold them, so there is nothing to invent when they are
/// absent and nothing to read that macOS has not defined.
enum TapEvent: Equatable {
    case keyboard(kind: KeyboardKind, flags: CGEventFlags, keyCode: CGKeyCode)
    case disabled(DisableReason)
    /// Anything else. The mask asks for nothing else, so this is the
    /// case that does not arrive.
    case ignored
}

private func keyboardKind(for type: CGEventType) -> KeyboardKind? {
    switch type {
    case .keyDown: return .keyDown
    case .keyUp: return .keyUp
    case .flagsChanged: return .flagsChanged
    default: return nil
    }
}

/// Classify one event, reading its keyboard fields only when the
/// kind has them.
///
/// The fields are behind a closure rather than read at the call
/// because they are undefined for a disable notification: the
/// keycode could be anything the field happens to hold, and
/// narrowing it to CGKeyCode traps on anything that does not fit.
/// Passing them lazily is what lets a test assert they go unread.
func tapEvent(for type: CGEventType,
              keyboardFields: () -> (flags: CGEventFlags, keyCode: CGKeyCode)) -> TapEvent {
    switch type {
    case .tapDisabledByTimeout:
        return .disabled(.timeout)
    case .tapDisabledByUserInput:
        return .disabled(.userInput)
    default:
        guard let kind = keyboardKind(for: type) else { return .ignored }
        let fields = keyboardFields()
        return .keyboard(kind: kind, flags: fields.flags, keyCode: fields.keyCode)
    }
}

/// What the tap callback should do with an event.
///
/// Separate from the effects so it can be tested: the callback is a C
/// function pointer holding a CGEvent and a tap port, neither of which
/// a test can construct, while the decision is a function of one
/// value.
enum TapAction: Equatable {
    /// Hand the event back unchanged.
    case passThrough
    /// Replace the event's flags with these.
    case swap(CGEventFlags)
    /// The event is the modifier key itself going down or up. Replace
    /// the flags and the keycode, so the key the application is told
    /// about is the one it has been told is held.
    case swapModifierKey(flags: CGEventFlags, keyCode: CGKeyCode)
    /// The tap is off and must be turned back on.
    case reEnable(DisableReason)
}

/// The command and option bits that move together.
///
/// A modifier arrives as a generic bit saying it is held and a
/// device-dependent bit saying which physical key it was. Applications
/// read both -- Ghostty treats option as alt by side -- so moving one
/// without the other claims option while the side bits say command.
private let swappablePairs: [(command: CGEventFlags, option: CGEventFlags)] = [
  (.maskCommand, .maskAlternate),
  (CGEventFlags(rawValue: UInt64(NX_DEVICELCMDKEYMASK)),
   CGEventFlags(rawValue: UInt64(NX_DEVICELALTKEYMASK))),
  (CGEventFlags(rawValue: UInt64(NX_DEVICERCMDKEYMASK)),
   CGEventFlags(rawValue: UInt64(NX_DEVICERALTKEYMASK))),
]

/// Exchange command for option in one set of flags, a pair at a time.
///
/// Each pair is exchanged independently and everything else is left
/// alone, so holding both leaves both held rather than clearing them,
/// and shift keeps whichever side it was on.
func swapModifiers(in flags: CGEventFlags) -> CGEventFlags {
    var swapped = flags
    for pair in swappablePairs {
        swapped.subtract([pair.command, pair.option])
        if flags.contains(pair.command) { swapped.insert(pair.option) }
        if flags.contains(pair.option) { swapped.insert(pair.command) }
    }
    return swapped
}

/// The key on the other side of the swap, for the event that reports
/// a modifier going down or up.
///
/// That event carries the physical key in its keycode, and that is
/// what applications read to decide which modifier changed. Rewriting
/// the flags alone would tell them the command key was pressed while
/// the command bit was clear, which reads as a release.
func swappedModifierKey(_ keyCode: CGKeyCode) -> CGKeyCode? {
    switch Int(keyCode) {
    case kVK_Command: return CGKeyCode(kVK_Option)
    case kVK_Option: return CGKeyCode(kVK_Command)
    case kVK_RightCommand: return CGKeyCode(kVK_RightOption)
    case kVK_RightOption: return CGKeyCode(kVK_RightCommand)
    default: return nil
    }
}

/// Decide what to do with one event.
///
/// Every event carries the whole modifier state, so the flags are
/// always exchanged: shift pressed while command is held carries
/// command, and has to agree with the events before it.
///
/// Exchanging relabels the two keys rather than ruling on chords, so
/// it needs no guard for holding both: the generic bits come back
/// unchanged and a command+option chord is delivered as it arrived,
/// with only the sides following the swap.
///
/// The keycode moves only for the events reporting a modifier itself,
/// which is how an application tracks what is down. A release carries
/// no modifier bits, so an unrelabelled one reports the release of a
/// key the application never saw pressed and leaves the swapped
/// modifier stuck.
func tapAction(for event: TapEvent) -> TapAction {
    switch event {
    case .disabled(let reason):
        return .reEnable(reason)

    case .ignored:
        return .passThrough

    case .keyboard(let kind, let flags, let keyCode):
        let swapped = swapModifiers(in: flags)
        if kind == .flagsChanged, let swappedKey = swappedModifierKey(keyCode) {
            return .swapModifierKey(flags: swapped, keyCode: swappedKey)
        }
        return swapped == flags ? .passThrough : .swap(swapped)
    }
}
