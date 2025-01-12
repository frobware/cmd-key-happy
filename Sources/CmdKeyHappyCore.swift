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

    private static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        guard let userInfo = userInfo else {
            CKHLog.error("Missing userInfo in callback")
            return Unmanaged.passUnretained(event)
        }

        let targetProcessID = event.getIntegerValueField(.eventTargetUnixProcessID)
        let tappedApp = Unmanaged<TappedApp>.fromOpaque(userInfo).takeUnretainedValue()
        guard tappedApp.pid == targetProcessID else {
            return Unmanaged.passUnretained(event)
        }

        guard event.flags.contains(.maskCommand) || event.flags.contains(.maskAlternate) else {
            return Unmanaged.passUnretained(event)
        }

        CKHLog.debug("option^=command for PID: \(tappedApp.pid), appName: \(tappedApp.name)")

        // Swap Command and Option modifier keys. symmetricDifference
        // performs XOR on the flags, which works here because we know
        // from the guard that exactly one of these modifiers is
        // pressed (not neither, not both). XOR will therefore remove
        // the pressed modifier and add the unpressed one in a single
        // operation.
        event.flags = event.flags.symmetricDifference([.maskCommand, .maskAlternate])
        return Unmanaged.passUnretained(event)
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

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue | 1 << CGEventType.flagsChanged.rawValue)
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
