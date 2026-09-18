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

class TappedApp {
    let pid: pid_t
    let name: String
    var tap: CFMachPort?

    init(pid: pid_t, name: String) {
        self.pid = pid
        self.name = name
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
    /// - Parameter appsToTap: List of application names to monitor
    func configure(appsToTap: [String]) {
        self.currentConfiguration = Set(appsToTap)
        untapAll()
        tapRunningApps()
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

    private func tapRunningApps() {
        for app in NSWorkspace.shared.runningApplications {
            guard let appName = app.localizedName,
                  currentConfiguration.contains(appName) else { continue }
            tapApp(for: app.processIdentifier, appName: appName)
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
        cleanup()
        CFRunLoopStop(self.runLoop)
    }

    func stop() {
        guard !isStopping else { return }
        isStopping = true
        untapAll()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func cleanup() {
        tappedApps.removeAll()
    }

    private func removeTap(forPid pid: pid_t) {
        guard let tappedApp = tappedApps[pid], let tap = tappedApp.tap else { return }

        CGEvent.tapEnable(tap: tap, enable: false)
        CFMachPortInvalidate(tap)

        if let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0) {
            CFRunLoopRemoveSource(self.runLoop, runLoopSource, .commonModes)
        }

        CKHLog.info("Removed event tap for PID: \(pid), appName: \(tappedApp.name)")
        tappedApps.removeValue(forKey: pid)
    }

    /// Gather, decide, act. The decision is `tapAction`, which is
    /// pure and tested; everything here is the effects it implies.
    private static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo = userInfo else {
            CKHLog.error("Missing userInfo in callback")
            return Unmanaged.passUnretained(event)
        }

        let tappedApp = Unmanaged<TappedApp>.fromOpaque(userInfo).takeUnretainedValue()
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let action = tapAction(
          for: type,
          flags: event.flags,
          keyCode: keyCode,
          targetPID: pid_t(event.getIntegerValueField(.eventTargetUnixProcessID)),
          tappedPID: tappedApp.pid)

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
            // the port is non-nil.
            //
            // The log line is what keeps this honest. A callback that
            // has genuinely become slow is disabled again immediately,
            // and `make show-errors` then shows a stream of these
            // rather than nothing at all.
            if let tap = tappedApp.tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            CKHLog.error("Event tap disabled (\(reason.description)) for PID \(tappedApp.pid), appName: \(tappedApp.name): re-enabled")
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
        if let tappedApp = tappedApps[pid], tappedApp.tap != nil {
            return
        }

        // keyUp as well as keyDown: an application told a key went
        // down under option and came up under command has no way to
        // pair the two, and the ones that track releases -- kitty's
        // keyboard protocol, Ghostty -- act on the difference.
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue
                                        | 1 << CGEventType.keyUp.rawValue
                                        | 1 << CGEventType.flagsChanged.rawValue)
        let tappedApp = tappedApps[pid] ?? TappedApp(pid: pid, name: appName)
        let userInfo = Unmanaged.passUnretained(tappedApp).toOpaque()

        guard let tap = CGEvent.tapCreate(
                tap: .cgAnnotatedSessionEventTap,
                place: .tailAppendEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: CmdKeyHappyCore.eventCallback,
                userInfo: userInfo
        ) else {
            let error = String(cString: strerror(errno))
            CKHLog.error("Failed to create event tap: \(error)")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(self.runLoop, runLoopSource, .commonModes)

        tappedApp.tap = tap
        tappedApps[pid] = tappedApp
        CKHLog.info("Event tap created for PID \(pid), appName: \(appName)")
    }

    deinit {
        cleanup()
    }
}
