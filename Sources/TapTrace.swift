import Carbon.HIToolbox
import CoreGraphics
import IOKit

/// A modifier, and the two bits that say which of its keys produced
/// it: a generic bit meaning "is held" and a device-dependent bit
/// meaning "and it was this one". They are one fact, and print as
/// one.
private struct TraceableModifier {
    let name: String
    let generic: CGEventFlags
    let left: CGEventFlags?
    let right: CGEventFlags?
}

private func deviceFlag(_ mask: Int32) -> CGEventFlags {
    CGEventFlags(rawValue: UInt64(mask))
}

private let traceableModifiers: [TraceableModifier] = [
  TraceableModifier(name: "cmd", generic: .maskCommand,
                    left: deviceFlag(NX_DEVICELCMDKEYMASK),
                    right: deviceFlag(NX_DEVICERCMDKEYMASK)),
  TraceableModifier(name: "opt", generic: .maskAlternate,
                    left: deviceFlag(NX_DEVICELALTKEYMASK),
                    right: deviceFlag(NX_DEVICERALTKEYMASK)),
  TraceableModifier(name: "shift", generic: .maskShift,
                    left: deviceFlag(NX_DEVICELSHIFTKEYMASK),
                    right: deviceFlag(NX_DEVICERSHIFTKEYMASK)),
  TraceableModifier(name: "ctrl", generic: .maskControl,
                    left: deviceFlag(NX_DEVICELCTLKEYMASK),
                    right: deviceFlag(NX_DEVICERCTLKEYMASK)),
  TraceableModifier(name: "fn", generic: .maskSecondaryFn, left: nil, right: nil),
  TraceableModifier(name: "caps", generic: .maskAlphaShift, left: nil, right: nil),
]

/// One entry per modifier held: `cmd(L)` is the left command key,
/// `cmd(L,R)` both of them, bare `cmd` a modifier whose event named no
/// key at all.
///
/// A side bit arriving without its modifier is printed on its own in
/// brackets, `(R-cmd)`. No keyboard produces that, so it is worth
/// seeing rather than rendering away.
private func describe(_ flags: CGEventFlags) -> String {
    var held: [String] = []
    for modifier in traceableModifiers {
        var sides: [String] = []
        if let left = modifier.left, flags.contains(left) { sides.append("L") }
        if let right = modifier.right, flags.contains(right) { sides.append("R") }

        if flags.contains(modifier.generic) {
            held.append(sides.isEmpty
                          ? modifier.name
                          : "\(modifier.name)(\(sides.joined(separator: ",")))")
        } else if !sides.isEmpty {
            held.append("(\(sides.map { "\($0)-\(modifier.name)" }.joined(separator: ",")))")
        }
    }
    return held.isEmpty ? "none" : held.joined(separator: ",")
}

/// The modifier keys by name, in the same vocabulary as the flags
/// above. On a modifier release the keycode is the only information in
/// the line.
private let modifierKeyNames: [CGKeyCode: String] = [
  CGKeyCode(kVK_Command): "L-cmd",
  CGKeyCode(kVK_RightCommand): "R-cmd",
  CGKeyCode(kVK_Option): "L-opt",
  CGKeyCode(kVK_RightOption): "R-opt",
  CGKeyCode(kVK_Shift): "L-shift",
  CGKeyCode(kVK_RightShift): "R-shift",
  CGKeyCode(kVK_Control): "L-ctrl",
  CGKeyCode(kVK_RightControl): "R-ctrl",
  CGKeyCode(kVK_CapsLock): "caps",
  CGKeyCode(kVK_Function): "fn",
]

private func describe(key keyCode: CGKeyCode) -> String {
    modifierKeyNames[keyCode] ?? "\(keyCode)"
}

private func describe(_ kind: KeyboardKind) -> String {
    switch kind {
    case .keyDown: return "keyDown"
    case .keyUp: return "keyUp"
    case .flagsChanged: return "flagsChanged"
    }
}

/// Pad to line columns up. Never truncate: the longest values are the
/// unusual ones.
private func padded(_ text: String, to width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

/// One line saying what arrived and what was delivered, or nil for an
/// event not worth a line.
///
/// Events carrying neither command nor option are dropped: a tapped
/// application receives every keystroke typed into it, and those bury
/// the rest. Events carrying one and left alone are kept and say
/// action=passthrough, which answers why a chord was not swapped.
///
/// Fields that moved are written twice, as .in and .out; fields that
/// did not are written once.
///
/// Anything that is not a keyboard event returns nil. A disabled tap
/// is already reported at error level, and saying it twice would make
/// a rare event look like two.
func tapTraceLine(app: String,
                  pid: pid_t,
                  event: TapEvent,
                  action: TapAction) -> String? {
    guard case .keyboard(let kind, let flags, let keyCode) = event else { return nil }

    let delivered: (keyCode: CGKeyCode, flags: CGEventFlags)
    switch action {
    case .passThrough:
        guard flags.contains(.maskCommand) || flags.contains(.maskAlternate) else { return nil }
        delivered = (keyCode, flags)
    case .swap(let swappedFlags):
        delivered = (keyCode, swappedFlags)
    case .swapModifierKey(let swappedFlags, let swappedKeyCode):
        delivered = (swappedKeyCode, swappedFlags)
    case .reEnable:
        return nil
    }

    // One name and one value when it arrived and left the same, `.in`
    // and `.out` when it did not. That is the whole of what the line
    // says: read across, and anything written twice was changed.
    let key = delivered.keyCode == keyCode
      ? "key=\(describe(key: keyCode))"
      : "key.in=\(describe(key: keyCode)) key.out=\(describe(key: delivered.keyCode))"
    let modifiers = delivered.flags == flags
      ? "modifiers=\(describe(flags))"
      : "modifiers.in=\(describe(flags)) modifiers.out=\(describe(delivered.flags))"

    return "\(padded("\(app)[\(pid)]", to: 18)) event=\(padded(describe(kind), to: 13))"
      + " \(padded(key, to: 27)) \(modifiers)"
}
