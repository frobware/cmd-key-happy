import ArgumentParser
import Foundation
import ApplicationServices

enum AccessibilityError: Error, LocalizedError {
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return """
              Accessibility permissions are required for keyboard monitoring.
                1. Open System Settings > Privacy & Security > Accessibility.
                2. Grant permission for this application.
                3. Run the application again.
              """
        }
    }
}

struct AccessibilityPermissions {
    static func checkPermissions() throws {
        let options = [
            "AXTrustedCheckOptionPrompt": true
        ] as CFDictionary

        if !AXIsProcessTrustedWithOptions(options) {
            throw AccessibilityError.permissionDenied
        }
    }
}

extension CmdKeyHappyCore {
    func checkPermissionsAndStart() throws {
        try AccessibilityPermissions.checkPermissions()
        start()
    }
}

class ConfigFileWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let callback: () -> Void
    private let path: String
    private var fileHandle: Int32 = -1

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

        let source = DispatchSource.makeFileSystemObjectSource(
          fileDescriptor: fileHandle,
          eventMask: .write,
          queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.callback()
        }
        source.setCancelHandler { [fileHandle] in
            close(fileHandle)
        }
        self.source = source
        source.resume()
        CKHLog.info("Started watching configuration file: \(path)")
    }

    func stop() {
        source?.cancel()
        source = nil
        CKHLog.info("Stopped watching configuration file: \(path)")
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
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Validates and resolves a path to ensure it points to a regular file.
    /// - Parameter path: Path to validate
    /// - Returns: The resolved path (if symlink)
    /// - Throws: ConfigError if validation fails
    func validatePath(_ path: String) throws -> String {
        let resolvedPath: String
        do {
            resolvedPath = try fileManager.destinationOfSymbolicLink(atPath: path)
        } catch {
            // Not a symlink, use original path.
            resolvedPath = path
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
              .filter { !$0.isEmpty }
        } catch {
            throw ConfigError.readError(path, error)  // Use original path in error
        }
    }
}

struct CmdKeyHappyApp: ParsableCommand {
    static let configuration = CommandConfiguration(
      commandName: "cmd-key-happy",
      abstract: "A utility to swap command and option keys for specific apps"
    )

    @Option(name: .shortAndLong, help: "Path to configuration file")
    private var config: String?

    @Flag(name: .long, help: "Run without console output")
    private var headless = false

    @Argument(help: "Names of apps to monitor")
    private var apps: [String] = []

    private var isUsingDefaultConfig = false

    private var configLoader: ConfigFileLoader {
        ConfigFileLoader()
    }

    mutating func validate() throws {
        if config == nil && apps.isEmpty {
            let paths = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true)
            guard let appSupport = paths.first else {
                throw ConfigError.failedToCreateDirectory("Could not determine Application Support directory path", NSError(domain: NSCocoaErrorDomain, code: -1))
            }

            let configDir = (appSupport as NSString).appendingPathComponent("com.frobware.cmd-key-happy")

            if !FileManager.default.fileExists(atPath: configDir) {
                do {
                    try FileManager.default.createDirectory(atPath: configDir, withIntermediateDirectories: true)
                } catch {
                    throw ConfigError.failedToCreateDirectory(configDir, error)
                }
            }

            config = (configDir as NSString).appendingPathComponent("config")
            isUsingDefaultConfig = true
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

        try AccessibilityPermissions.checkPermissions()
        cmdKeyHappy.start()
    }
}

CmdKeyHappyApp.main()
