import CoreGraphics

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
/// Separating the decision from the effects is what makes it testable:
/// the callback is a C function pointer holding a CGEvent and a tap
/// port, none of which can be constructed in a test, whereas the
/// question it answers is a total function of four values.
enum TapAction: Equatable {
    /// Hand the event back unchanged.
    case passThrough
    /// Replace the event's flags with these.
    case swap(CGEventFlags)
    /// The tap is off and must be turned back on.
    case reEnable(DisableReason)
}

/// Decide what to do with one event.
///
/// The swap is a symmetric difference of the two modifier bits, which
/// is only correct when exactly one of them is held: with both, XOR
/// clears both and the application receives a bare keypress. Hence the
/// inequality rather than a disjunction.
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

    return .swap(flags.symmetricDifference([.maskCommand, .maskAlternate]))
}
