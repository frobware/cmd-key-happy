import ArgumentParser
import Foundation
import ApplicationServices

enum AccessibilityError: Error, LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return """
              Accessibility permission is required to monitor the keyboard.
                1. Open System Settings > Privacy & Security > Accessibility.
                2. Switch on CmdKeyHappy.app. It lists itself there, unchecked,
                   as soon as this asks -- which is now.
              Under launchd that is all: it retries and comes up on its own.
              Started by hand, start it again.
              """
        }
    }
}

struct AccessibilityPermissions {
    /// - Parameter prompt: When true, macOS opens the Accessibility
    ///   settings pane on failure. Pass false for unattended runs:
    ///   under launchd with KeepAlive the check retries every few
    ///   seconds and each prompt would reopen System Settings.
    static func checkPermissions(prompt: Bool) throws {
        let options = [
            "AXTrustedCheckOptionPrompt": prompt
        ] as CFDictionary

        if !AXIsProcessTrustedWithOptions(options) {
            throw AccessibilityError.permissionDenied
        }
    }
}

/// Watches the configuration file for changes.
///
/// A descriptor names an inode, not a path. An atomic save, and emacs
/// renaming the original aside for its backup, leave the descriptor on
/// an inode nothing writes to again, so rename and delete are watched
/// as well as write and the watch moves to whatever is at the path
/// afterwards. While the path is empty, the directory holding the file
/// is watched until it comes back.
class ConfigFileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let callback: () -> Void
    private let path: String
    private var fileHandle: Int32 = -1

    /// Where to watch while the path is empty.
    ///
    /// The directory holding the resolved target, not the one holding
    /// the path: a config linked in from a dotfiles checkout is edited
    /// where the target lives. Taken from the open descriptor, so no
    /// second resolution can race the editor.
    ///
    /// A link repointed at a different file is not followed.
    private var directoryToWatch: String?

    /// Initialise with a path and optional file handle. If a file
    /// handle is provided, the watcher takes ownership and will close
    /// it when stopped.
    init(path: String, fileHandle: Int32? = nil, callback: @escaping () -> Void) {
        self.path = path
        self.fileHandle = fileHandle ?? -1
        self.callback = callback
    }

    func start() throws {
        if fileHandle == -1 {
            fileHandle = open(path, O_EVTONLY)
            guard fileHandle != -1 else {
                let error = String(cString: strerror(errno))
                throw ConfigError.readError(path, NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: error]))
            }
        }

        watchFile(fileHandle)
        // The source owns it now and closes it when cancelled.
        fileHandle = -1
        CKHLog.info("Started watching configuration file: \(path)")
    }

    func stop() {
        source?.cancel()
        source = nil
        CKHLog.info("Stopped watching configuration file: \(path)")
    }

    /// Watch the file this descriptor names, replacing any current
    /// watch. The source takes ownership of the descriptor.
    private func watchFile(_ descriptor: Int32) {
        var resolved = [UInt8](repeating: 0, count: Int(PATH_MAX))
        let found = resolved.withUnsafeMutableBytes { buffer -> Bool in
            guard let start = buffer.baseAddress else { return false }
            return fcntl(descriptor, F_GETPATH, start) != -1
        }
        if found {
            let target = String(decoding: resolved.prefix { $0 != 0 }, as: UTF8.self)
            directoryToWatch = (target as NSString).deletingLastPathComponent
        }

        install(descriptor: descriptor, eventMask: [.write, .rename, .delete]) { [weak self] events in
            guard let self else { return }
            // Re-arm before reporting, so an edit landing on the new
            // file while the callback runs is still seen.
            if !events.isDisjoint(with: [.rename, .delete]) {
                followPath()
            }
            callback()
        }
    }

    /// The file has left the path. Watch what is there now, or the
    /// directory until something is.
    private func followPath() {
        let descriptor = open(path, O_EVTONLY)
        if descriptor != -1 {
            watchFile(descriptor)
        } else {
            watchDirectory()
        }
    }

    private func watchDirectory() {
        let parent = directoryToWatch ?? (path as NSString).deletingLastPathComponent
        let directory = parent.isEmpty ? "." : parent
        let descriptor = open(directory, O_EVTONLY)
        guard descriptor != -1 else {
            let error = String(cString: strerror(errno))
            CKHLog.error("Cannot watch \(directory): \(error) - configuration changes will no longer be noticed")
            return
        }

        let followReappearedFile = { [weak self] in
            guard let self else { return }
            let descriptor = open(path, O_EVTONLY)
            guard descriptor != -1 else { return }
            watchFile(descriptor)
            callback()
        }

        // resume() can return before the vnode watch is registered.
        // Recheck once registration finishes, so a file recreated before
        // the directory watch became active is still followed and read.
        install(descriptor: descriptor, eventMask: .write,
                onRegistration: followReappearedFile) { _ in
            followReappearedFile()
        }
    }

    /// Install a source, cancelling whatever was watched before. Safe
    /// to call from inside the previous source's own handler.
    private func install(descriptor: Int32,
                         eventMask: DispatchSource.FileSystemEvent,
                         onRegistration: (() -> Void)? = nil,
                         handler: @escaping (DispatchSource.FileSystemEvent) -> Void) {
        source?.cancel()
        let source = DispatchSource.makeFileSystemObjectSource(
          fileDescriptor: descriptor,
          eventMask: eventMask,
          queue: .main
        )
        source.setEventHandler { [weak source] in
            guard let events = source?.data else { return }
            handler(events)
        }
        if let onRegistration {
            source.setRegistrationHandler { [weak source] in
                guard let source, !source.isCancelled else { return }
                onRegistration()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        self.source = source
        source.resume()
    }

    deinit {
        stop()
    }
}

enum ConfigError: Error, LocalizedError {
    case fileNotFound(String)
    case readError(String, Error)
    case notRegularFile(String)
    case failedToCreateDirectory(String, Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "\(path): No such file or directory"
        case .readError(let path, let error):
            return "\(path): \(error.localizedDescription)"
        case .notRegularFile(let path):
            return "\(path): Not a regular file"
        case .failedToCreateDirectory(let path, let error):
            return "\(path): Failed to create directory: \(error.localizedDescription)"
        }
    }
}

struct ConfigFileLoader {
    /// What the daemon writes when it finds no configuration file.
    ///
    /// Every line is a comment, so a fresh install taps nothing until
    /// you list an application.
    static let starterConfig = """
      # One application name per line, spelled as it appears in the
      # application list -- the name under the icon, not the bundle id.
      # Saving this file takes effect at once; there is nothing to
      # restart. Lines starting with # are ignored.
      #
      # Check what you have written with: make parse-config
      #
      # For example:
      #
      # Alacritty
      # Ghostty
      # kitty
      # Terminal
      # WezTerm

      """

    /// The configuration file, created from the starter template if it
    /// is not there yet, along with the directory holding it.
    ///
    /// Registration calls this as well as the daemon: on a new machine
    /// the daemon does not run until the Accessibility permission
    /// exists, and the file has to be there to be edited.
    ///
    /// An existing file is never touched.
    @discardableResult
    static func ensureConfig(in directory: String,
                             fileManager: FileManager = .default) throws -> String {
        if !fileManager.fileExists(atPath: directory) {
            do {
                try fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
            } catch {
                throw ConfigError.failedToCreateDirectory(directory, error)
            }
        }

        let path = (directory as NSString).appendingPathComponent("config")
        if !fileManager.fileExists(atPath: path) {
            // createFile reports failure by returning false. Unreported,
            // registration says it wrote a config that is not there and
            // the daemon fails on it later.
            guard fileManager.createFile(atPath: path, contents: Data(starterConfig.utf8)) else {
                throw ConfigError.readError(
                  path, NSError(domain: NSPOSIXErrorDomain, code: Int(errno),
                                userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]))
            }
        }
        return path
    }

    /// Where that lives when nobody passes --config.
    static func defaultConfigDirectory() throws -> String {
        let paths = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
        guard let appSupport = paths.first else {
            throw ConfigError.failedToCreateDirectory(
              "Could not determine Application Support directory path",
              NSError(domain: NSCocoaErrorDomain, code: -1))
        }
        return (appSupport as NSString).appendingPathComponent("com.frobware.cmd-key-happy")
    }

    /// The kernel's own limit before ELOOP, so a chain refused here is
    /// one the open would refuse, and a cycle terminates.
    private static let symlinkChainLimit = 32

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Validates and resolves a path to ensure it points to a regular file.
    /// - Parameter path: Path to validate
    /// - Returns: The fully resolved path
    /// - Throws: ConfigError if validation fails
    func validatePath(_ path: String) throws -> String {
        // A symlink's target is stored as written, so a relative one
        // is relative to the directory holding the link, not to
        // wherever we happen to be running. Under launchd the daemon's
        // working directory is /, so resolving it there would report a
        // config that plainly exists as missing.
        //
        // The chain can be longer than one link: a config linked into
        // place whose target is itself a link is what a dotfiles
        // manager leaves behind. Follow it to the end, or until the
        // limit, past which the path does not resolve and the checks
        // below report it against the path the caller gave.
        var resolvedPath = path
        for _ in 0..<Self.symlinkChainLimit {
            guard let target = try? fileManager.destinationOfSymbolicLink(atPath: resolvedPath) else {
                break
            }
            resolvedPath = (target as NSString).isAbsolutePath
              ? target
              : ((resolvedPath as NSString).deletingLastPathComponent as NSString)
                  .appendingPathComponent(target)
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: resolvedPath, isDirectory: &isDirectory) else {
            // Use original path in error.
            throw ConfigError.fileNotFound(path)
        }

        guard !isDirectory.boolValue else {
            // Use original path in error.
            throw ConfigError.notRegularFile(path)
        }

        // Check that the final destination is a regular file.
        let attributes = try? fileManager.attributesOfItem(atPath: resolvedPath)
        let fileType = attributes?[.type] as? FileAttributeType
        guard fileType == .typeRegular else {
            // Use original path in error.
            throw ConfigError.notRegularFile(path)
        }

        return resolvedPath
    }

    /// Loads and validates a configuration file
    /// - Parameter path: Path to the configuration file
    /// - Returns: Array of non-empty lines from the file
    /// - Throws: ConfigError if validation or reading fails
    func loadConfigFile(_ path: String?) throws -> [String] {
        guard let path = path else { return [] }

        let resolvedPath = try validatePath(path)

        do {
            let fileContents = try String(contentsOfFile: resolvedPath, encoding: .utf8)
            return fileContents
              .split(separator: "\n")
              .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
              .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        } catch {
            throw ConfigError.readError(path, error)  // Use original path in error
        }
    }
}

/// Root command. It carries no options or arguments of its own; the
/// daemon lives in the `run` subcommand. A root command declaring a
/// positional array swallows subcommand names as positionals, which
/// would parse `cmd-key-happy register` as "monitor an app called
/// register". `defaultSubcommand` keeps a bare `cmd-key-happy`
/// running the daemon.
struct CmdKeyHappyApp: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "cmd-key-happy",
      abstract: "A utility to swap command and option keys for specific apps",
      subcommands: [
        DaemonCommand.self,
        RegisterCommand.self,
        UnregisterCommand.self,
        StatusCommand.self,
        VersionCommand.self,
        CheckInstallCommand.self,
        WriteIconCommand.self,
      ],
      defaultSubcommand: DaemonCommand.self
    )
}

struct DaemonCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "run",
      abstract: "Run the key-swapping daemon"
    )

    @Option(name: .shortAndLong, help: "Path to configuration file")
    private var config: String?

    @Flag(name: .long, help: "Run without console output")
    private var headless = false

    @Flag(name: [.customShort("p"), .customLong("parse-config")], help: "Parse the configuration file and exit")
    private var parseConfig = false

    @Argument(help: "Names of apps to monitor")
    private var apps: [String] = []

    private var isUsingDefaultConfig = false

    private var configLoader: ConfigFileLoader {
        ConfigFileLoader()
    }

    mutating func validate() throws {
        guard config == nil && apps.isEmpty else { return }

        let directory = try ConfigFileLoader.defaultConfigDirectory()
        isUsingDefaultConfig = true

        // --parse-config answers a question about a file; it does not
        // get to create one. Point at where the file would be and let
        // the loader report that it is not there.
        if parseConfig {
            config = (directory as NSString).appendingPathComponent("config")
        } else {
            config = try ConfigFileLoader.ensureConfig(in: directory)
        }
    }

    private func setupConfigFileWatcher(cmdKeyHappy: CmdKeyHappyCore, fileHandle: Int32) -> ConfigFileWatcher? {
        guard let configPath = config, apps.isEmpty else {
            return nil
        }

        return ConfigFileWatcher(path: configPath, fileHandle: fileHandle) { [self] in
            do {
                let newApps = try configLoader.loadConfigFile(config)
                cmdKeyHappy.configure(appsToTap: newApps)
                if newApps.isEmpty {
                    CKHLog.info("Configuration reloaded: no apps configured")
                } else {
                    CKHLog.info("Configuration reloaded: monitoring apps: [\(newApps.joined(separator: ", "))]")
                }
            } catch ConfigError.fileNotFound(let path) where isUsingDefaultConfig {
                CKHLog.info("Configuration file removed: \(path) - continuing with empty configuration")
                cmdKeyHappy.configure(appsToTap: [])
            } catch ConfigError.notRegularFile(let path) {
                CKHLog.error("Configuration file is no longer valid: \(path) - continuing with previous configuration")
            } catch {
                CKHLog.error("Failed to reload configuration: \(error.localizedDescription) - continuing with previous configuration")
            }
        }
    }

    func run() throws {
        if parseConfig {
            _ = try configLoader.loadConfigFile(config)
            return
        }

        let signalHandler = SignalHandler()
        let cmdKeyHappy = CmdKeyHappyCore()

        var initialApps: [String]
        var configFileWatcher: ConfigFileWatcher?

        if !apps.isEmpty {
            initialApps = apps
        } else {
            let fileHandle = open(config!, O_EVTONLY)
            if fileHandle != -1 {
                do {
                    initialApps = try configLoader.loadConfigFile(config)
                    if initialApps.isEmpty {
                        CKHLog.info("Starting with empty configuration")
                    }
                    configFileWatcher = setupConfigFileWatcher(cmdKeyHappy: cmdKeyHappy, fileHandle: fileHandle)
                    try configFileWatcher?.start()
                } catch ConfigError.fileNotFound(let path) where isUsingDefaultConfig {
                    CKHLog.info("No configuration file found at default path: \(path) - continuing with empty configuration")
                    initialApps = []
                    close(fileHandle)
                } catch {
                    close(fileHandle)
                    throw error
                }
            } else {
                let error = String(cString: strerror(errno))
                throw ConfigError.readError(config!, NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: error]))
            }
        }

        cmdKeyHappy.configure(appsToTap: initialApps)

        signalHandler.addHandler(for: [SIGTERM, SIGINT]) { signo in
            CKHLog.info("Received shutdown signal: Initiating shutdown...")
            configFileWatcher?.stop()
            cmdKeyHappy.shutdown()
        }

        // A signal is the only way to ask a daemon with no UI and no
        // socket. SIGUSR1 rather than SIGHUP, which means reload the
        // configuration.
        signalHandler.addHandler(for: [SIGUSR1]) { _ in
            let enabled = CKHLog.toggleTracing()
            // Notice, like the trace itself: this line says why the
            // log is full of keystrokes, and has to survive as long.
            CKHLog.notice("Received SIGUSR1: event tracing \(enabled ? "enabled" : "disabled")")
        }

        signalHandler.addHandler(for: [SIGHUP]) { _ in
            CKHLog.info("Received SIGHUP: Reloading configuration (note: file watching is enabled)")
            if !apps.isEmpty {
                CKHLog.info("Ignoring SIGHUP as apps were specified via command line")
                return
            }
            do {
                let newApps = try configLoader.loadConfigFile(config)
                cmdKeyHappy.configure(appsToTap: newApps)
                if newApps.isEmpty {
                    CKHLog.info("Configuration reloaded: no apps configured")
                } else {
                    CKHLog.info("Configuration reloaded: monitoring apps: [\(newApps.joined(separator: ", "))]")
                }
            } catch {
                CKHLog.error("Failed to reload configuration: \(error.localizedDescription) - continuing with previous configuration")
            }
        }

        try AccessibilityPermissions.checkPermissions(prompt: !headless)
        CKHLog.info(BuildMetadata.current().shortLine)
        cmdKeyHappy.start()
    }
}

do {
    var command = try CmdKeyHappyApp.parseAsRoot()
    try command.run()
} catch {
    // Fatal errors must reach the unified log: under launchd stderr
    // is discarded, and info-level os_log messages are not persisted.
    // Only when there is no terminal: exit(withError:) below reports
    // to stderr, so logging as well would print the failure twice.
    if !CKHLog.isConsoleEnabled, !CmdKeyHappyApp.exitCode(for: error).isSuccess {
        // A missing accessibility grant is the expected state before
        // the grant is given, and launchd retries every few seconds
        // until it is. Reporting that at fault level would repeat the
        // loudest level macOS has, indefinitely, for a condition that
        // resolves itself. Keep fault for the unexpected.
        if error is AccessibilityError {
            CKHLog.error(CmdKeyHappyApp.message(for: error))
        } else {
            CKHLog.critical(CmdKeyHappyApp.message(for: error))
        }
    }
    CmdKeyHappyApp.exit(withError: error)
}
