import Cocoa
import CoreGraphics
import Dispatch
import Foundation
import os.log

extension CGEventFlags {
    var description: String {
        var parts: [String] = []
        if contains(.maskShift) { parts.append("shift") }
        if contains(.maskControl) { parts.append("control") }
        if contains(.maskAlternate) { parts.append("option") }
        if contains(.maskCommand) { parts.append("command") }
        if contains(.maskSecondaryFn) { parts.append("fn") }
        if contains(.maskNumericPad) { parts.append("numpad") }
        if contains(.maskHelp) { parts.append("help") }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }
}

/// The application a tap was created for, as the callback sees it.
///
/// Handed to CoreGraphics as an opaque pointer, so it has to be a
/// class and has to outlive its tap. It cannot hold the tap itself:
/// CoreGraphics wants this pointer before it will create one. The
/// core holds the port, and re-enabling goes back through it.
private final class TapTarget {
    let pid: pid_t
    let name: String
    private unowned let core: CmdKeyHappyCore

    init(pid: pid_t, name: String, core: CmdKeyHappyCore) {
        self.pid = pid
        self.name = name
        self.core = core
    }

    func reEnableTap() {
        core.reEnableTap(forPid: pid)
    }
}

/// An application with a tap.
///
/// Creating one creates the tap, and releasing one tears it down, so a
/// tap cannot exist without something holding it and cannot be
/// abandoned while CoreGraphics still has the pointer it was given.
/// `deinit` runs before stored properties are released, so the target
/// is still alive while the port is being invalidated.
///
/// That the tap exists is not that it is enabled: macOS switches taps
/// off, and that is reported rather than prevented.
private final class TappedApp {
    let target: TapTarget
    let tap: CFMachPort
    private let runLoop: CFRunLoop

    /// keyUp as well as keyDown: an application told a key went down
    /// under option and came up under command has no way to pair the
    /// two, and the ones that track releases -- kitty's keyboard
    /// protocol, Ghostty -- act on the difference.
    private static let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue
                                                   | 1 << CGEventType.keyUp.rawValue
                                                   | 1 << CGEventType.flagsChanged.rawValue)

    init?(pid: pid_t, name: String, core: CmdKeyHappyCore,
          runLoop: CFRunLoop, callback: CGEventTapCallBack) {
        // Unretained: this object owns the target from here on, and it
        // invalidates the tap before letting go of it.
        let target = TapTarget(pid: pid, name: name, core: core)
        // Per process, so the window server delivers only the events
        // routed to this one. A session tap would see every keystroke
        // in the session and leave the filtering to us, once for each
        // application being tapped.
        guard let tap = CGEvent.tapCreateForPid(
                pid: pid,
                place: .tailAppendEventTap,
                options: .defaultTap,
                eventsOfInterest: Self.eventMask,
                callback: callback,
                userInfo: Unmanaged.passUnretained(target).toOpaque()
        ) else { return nil }

        self.target = target
        self.tap = tap
        self.runLoop = runLoop

        // A tap that never reaches the run loop delivers nothing,
        // while the entry claims the application is tapped and the
        // check in tapApp stops it being tried again. Failing here
        // instead tears the tap down: the stored properties are set,
        // so returning nil runs deinit.
        guard let source = CFMachPortCreateRunLoopSource(nil, tap, 0) else { return nil }
        CFRunLoopAddSource(runLoop, source, .commonModes)
    }

    deinit {
        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)
        if let source = CFMachPortCreateRunLoopSource(nil, tap, 0) {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
        }
    }
}

class CmdKeyHappyCore {
    private var isStopping = false
    private var tappedApps: [pid_t: TappedApp] = [:]
    private let runLoop: CFRunLoop
    private var currentConfiguration: Set<String>

    init(runLoop: CFRunLoop = CFRunLoopGetMain()) {
        self.runLoop = runLoop
        self.currentConfiguration = []
    }

    /// Configures and starts monitoring for the specified applications.
    ///
    /// Applies what changed. Tearing every tap down and building them
    /// all again would stop swapping for every application for a
    /// window, and rebuild taps macOS has no complaint about.
    ///
    /// - Parameter appsToTap: List of application names to monitor
    func configure(appsToTap: [String]) {
        self.currentConfiguration = Set(appsToTap)

        let running = NSWorkspace.shared.runningApplications.compactMap { app -> RunningApp? in
            guard let name = app.localizedName else { return nil }
            return RunningApp(pid: app.processIdentifier, name: name)
        }

        let plan = tapPlan(desired: currentConfiguration,
                           running: running,
                           tapped: Set(tappedApps.keys))

        for pid in plan.remove {
            removeTap(forPid: pid)
        }
        for app in plan.create {
            tapApp(for: app.pid, appName: app.name)
        }
    }

    /// Starts the event loop and application monitoring
    func start() {
        setupWorkspaceNotifications()
        CFRunLoopRun()
    }

    private func untapAll() {
        for pid in tappedApps.keys {
            removeTap(forPid: pid)
        }
    }

    private func setupWorkspaceNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )
    }

    func shutdown() {
        stop()
        CFRunLoopStop(self.runLoop)
    }

    func stop() {
        guard !isStopping else { return }
        isStopping = true
        untapAll()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func removeTap(forPid pid: pid_t) {
        guard let tappedApp = tappedApps.removeValue(forKey: pid) else { return }
        CKHLog.info("Removed event tap for PID: \(pid), appName: \(tappedApp.target.name)")
    }

    /// Turn a tap macOS switched off back on. Called from the
    /// callback, which is handed the target rather than the port.
    fileprivate func reEnableTap(forPid pid: pid_t) {
        guard let tappedApp = tappedApps[pid] else { return }
        CGEvent.tapEnable(tap: tappedApp.tap, enable: true)
    }

    /// Gather, decide, act. The decision is `tapAction`, which is
    /// pure and tested; everything here is the effects it implies.
    private static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo = userInfo else {
            CKHLog.error("Missing userInfo in callback")
            return Unmanaged.passUnretained(event)
        }

        let target = Unmanaged<TapTarget>.fromOpaque(userInfo).takeUnretainedValue()
        let flags = event.flags
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let action = tapAction(for: type, flags: flags, keyCode: keyCode)

        // Traced before the event is altered, so the line reports what
        // arrived rather than what we are about to hand on. The check
        // is what keeps an unwanted trace off the cost of an ordinary
        // keystroke.
        if CKHLog.isTracingEnabled,
           let trace = tapTraceLine(app: target.name, pid: target.pid, type: type,
                                    keyCode: keyCode, flags: flags, action: action) {
            // Notice, not debug and not info: you asked for this, so
            // it is neither noise to discard nor something to lose.
            // Debug is dropped by the unified log unless enabled for
            // the subsystem as root; info is held in memory and ages
            // out, so a trace you turned on and read an hour later
            // would be gone. Notice is written to disk, which is what
            // makes the signal enough on its own and lets show-logs
            // answer afterwards.
            CKHLog.notice(trace)
        }

        switch action {
        case .passThrough:
            return Unmanaged.passUnretained(event)

        case .swap(let flags):
            event.flags = flags
            return Unmanaged.passUnretained(event)

        case .swapModifierKey(let flags, let swappedKeyCode):
            event.flags = flags
            event.setIntegerValueField(.keyboardEventKeycode, value: Int64(swappedKeyCode))
            return Unmanaged.passUnretained(event)

        case .reEnable(let reason):
            // macOS switches an active tap off if the callback takes
            // too long, or under certain input conditions. The tap
            // does not come back on its own and the process keeps
            // running, so launchd's KeepAlive cannot restart it:
            // nothing else will, because tapApp returns early while
            // an entry exists.
            //
            // The log line is what keeps this honest. A callback that
            // has genuinely become slow is disabled again immediately,
            // and `make show-errors` then shows a stream of these
            // rather than nothing at all.
            target.reEnableTap()
            CKHLog.error("Event tap disabled (\(reason.description)) for PID \(target.pid), appName: \(target.name): re-enabled")
            return nil
        }
    }

    @objc private func handleAppLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let appName = app.localizedName,
              currentConfiguration.contains(appName) else {
            return
        }

        tapApp(for: app.processIdentifier, appName: appName)
    }

    @objc private func handleAppTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return
        }

        removeTap(forPid: app.processIdentifier)
    }

    private func tapApp(for pid: pid_t, appName: String) {
        if tappedApps[pid] != nil { return }

        guard let tapped = TappedApp(pid: pid, name: appName, core: self,
                                     runLoop: self.runLoop,
                                     callback: CmdKeyHappyCore.eventCallback) else {
            // No reason: tapCreateForPid does not set errno, and the
            // value left there by an unrelated call reads as one. The
            // accessibility check has already passed by here, so what
            // remains is a process that went away between the launch
            // notification and this call.
            CKHLog.error("Failed to create event tap for PID \(pid), appName: \(appName)")
            return
        }

        tappedApps[pid] = tapped
        CKHLog.info("Event tap created for PID \(pid), appName: \(appName)")
    }
}
