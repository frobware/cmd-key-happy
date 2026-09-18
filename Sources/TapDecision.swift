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

/// What the tap callback should do with an event.
///
/// Separate from the effects so it can be tested: the callback is a C
/// function pointer holding a CGEvent and a tap port, neither of which
/// a test can construct, while the decision is a function of four
/// values.
enum TapAction: Equatable {
    /// Hand the event back unchanged.
    case passThrough
    /// Replace the event's flags with these.
    case swap(CGEventFlags)
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

/// Decide what to do with one event.
///
/// A chord holding both command and option is left alone, as it has
/// been in every implementation of this: there is no swap to make,
/// only two keys to leave where they are.
func tapAction(for type: CGEventType,
               flags: CGEventFlags,
               targetPID: pid_t,
               tappedPID: pid_t) -> TapAction {
    if type == .tapDisabledByTimeout {
        return .reEnable(.timeout)
    }
    if type == .tapDisabledByUserInput {
        return .reEnable(.userInput)
    }
    guard type == .keyDown else { return .passThrough }
    guard targetPID == tappedPID else { return .passThrough }

    let command = flags.contains(.maskCommand)
    let option = flags.contains(.maskAlternate)
    guard command != option else { return .passThrough }

    return .swap(swapModifiers(in: flags))
}
