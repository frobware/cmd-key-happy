import ArgumentParser
import Foundation
import ServiceManagement

/// Login-item management and build introspection.
///
/// cmd-key-happy is supervised by a LaunchAgent plist embedded in the
/// bundle at Contents/Library/LaunchAgents, registered through
/// SMAppService.agent. That keeps the job attached to the bundle's
/// code signature, which is what the accessibility (TCC) grant is
/// keyed on, and gives the daemon a single entry in System Settings >
/// General > Login Items.

private let agentPlistName = "com.frobware.cmd-key-happy.agent.plist"

/// A runtime failure carrying a message that is ready to print.
/// Distinct from ValidationError, which appends the command's usage
/// string: that belongs on a mistyped argument, not on a registration
/// that failed.
struct LoginItemError: Error, CustomStringConvertible {
    let description: String
}

private var agentService: SMAppService {
    SMAppService.agent(plistName: agentPlistName)
}

private func describe(_ status: SMAppService.Status) -> String {
    let name: String
    switch status {
    case .notRegistered:    name = "notRegistered"
    case .enabled:          name = "enabled"
    case .requiresApproval: name = "requiresApproval"
    case .notFound:         name = "notFound"
    @unknown default:       name = "unknown"
    }
    return "\(name) (\(status.rawValue))"
}

/// Build metadata injected into the bundled Info.plist by `make
/// bundle`. Reports "unknown" when the binary is run outside its
/// bundle or the Makefile was bypassed.
struct BuildMetadata {
    let commitHash: String
    let describe: String
    let branch: String
    let buildDate: String
    let bundleIdentifier: String
    let bundlePath: String

    static func current() -> BuildMetadata {
        let info = Bundle.main.infoDictionary ?? [:]
        func string(_ key: String) -> String {
            (info[key] as? String) ?? "unknown"
        }
        return BuildMetadata(
          commitHash: string("GitCommitHash"),
          describe: string("GitDescribe"),
          branch: string("GitBranch"),
          buildDate: string("BuildDate"),
          bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
          bundlePath: Bundle.main.bundlePath
        )
    }

    var shortLine: String {
        "cmd-key-happy \(describe) (\(branch)) built \(buildDate)"
    }
}

/// True when the running bundle sits in one of the two locations
/// macOS treats as installed. Registering from anywhere else would
/// record a login item pointing at a build tree.
private func isInstalledBundle() -> Bool {
    // Compare the containing directory rather than a string prefix:
    // appendingPathComponent drops the trailing slash, so a prefix
    // test would also accept ~/ApplicationsElsewhere/X.app.
    let parent = (Bundle.main.bundlePath as NSString).deletingLastPathComponent
    let homeApps = (NSHomeDirectory() as NSString).appendingPathComponent("Applications")
    return parent == "/Applications" || parent == homeApps
}

struct RegisterCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "register",
      abstract: "Register the bundled LaunchAgent as a login item"
    )

    func run() throws {
        // Refuse from a build-tree bundle. `make register` targets
        // the installed path, so this fires only when the binary is
        // invoked by hand.
        guard isInstalledBundle() else {
            throw LoginItemError(description: """
              register refused -- bundle is not installed.
                bundlePath: \(Bundle.main.bundlePath)
                Install with: make install
              """)
        }

        let service = agentService
        do {
            try service.register()
        } catch {
            let nsError = error as NSError
            throw LoginItemError(description: """
              register failed: \(nsError.domain) code=\(nsError.code)
                \(nsError.localizedDescription)
                bundlePath: \(Bundle.main.bundlePath)
              """)
        }

        print("cmd-key-happy: registered as a login item")
        print("  status:     \(describe(service.status))")
        print("  bundlePath: \(Bundle.main.bundlePath)")
    }
}

struct UnregisterCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "unregister",
      abstract: "Unregister the bundled LaunchAgent"
    )

    // No install-location guard: unregister exists to clean up, and a
    // stale registration may name a bundle that has moved or gone.
    func run() throws {
        let service = agentService
        do {
            try service.unregister()
        } catch {
            let nsError = error as NSError
            throw LoginItemError(description: """
              unregister failed: \(nsError.domain) code=\(nsError.code)
                \(nsError.localizedDescription)
                bundlePath: \(Bundle.main.bundlePath)
              """)
        }

        print("cmd-key-happy: unregistered")
        print("  bundlePath: \(Bundle.main.bundlePath)")
    }
}

struct StatusCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "status",
      abstract: "Print the LaunchAgent registration status"
    )

    func run() throws {
        print("cmd-key-happy: login-item status")
        print("  plist:      \(agentPlistName)")
        print("  status:     \(describe(agentService.status))")
        print("  bundlePath: \(Bundle.main.bundlePath)")
    }
}

struct VersionCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "version",
      abstract: "Print build metadata baked into the bundle"
    )

    func run() throws {
        let meta = BuildMetadata.current()
        print("cmd-key-happy")
        print("  commit:     \(meta.commitHash)")
        print("  describe:   \(meta.describe)")
        print("  branch:     \(meta.branch)")
        print("  build date: \(meta.buildDate)")
        print("  bundle id:  \(meta.bundleIdentifier)")
        print("  bundle:     \(meta.bundlePath)")
    }
}
