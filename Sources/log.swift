import Foundation
import os.log

struct CKHLog {
    /// Matches CFBundleIdentifier, which is what `log --subsystem`
    /// expects. The Makefile derives its log targets from $(BUNDLE_ID)
    /// and requires this to agree.
    private static let logger = Logger(subsystem: "com.frobware.cmd-key-happy", category: "default")
    /// Whether output goes to the console rather than the unified log.
    /// Only launchd passes --headless, so this also answers whether a
    /// person started the daemon.
    static let isConsoleEnabled = !CommandLine.arguments.contains("--headless")

    /// Whether anyone has asked for the event trace.
    ///
    /// A run started by hand starts with it on, under launchd with it
    /// off; SIGUSR1 decides from then on in both.
    ///
    /// Read before a trace line is built. The tap sees every keystroke
    /// the tapped application receives, and macOS switches off a tap
    /// whose callback is too slow, so an unwanted trace costs this
    /// check and nothing more.
    static var isTracingEnabled: Bool {
        isTracingRequested
    }

    /// Written from a signal source bound to the main queue and read
    /// from the tap callback on the main run loop: one thread, so a
    /// plain Bool is enough.
    nonisolated(unsafe) private(set) static var isTracingRequested = isConsoleEnabled

    /// Turn the trace on or off, returning what it now is.
    static func toggleTracing() -> Bool {
        isTracingRequested.toggle()
        return isTracingRequested
    }

    enum LogLevel: String {
        /// notice is the unified log's "default" level and the
        /// cheapest one written to disk. info and debug are held in
        /// memory and age out.
        case info, debug, notice, warning, error, critical
    }

    static func info(_ message: String) {
        logMessage(level: .info, message: message)
    }

    static func debug(_ message: String) {
        logMessage(level: .debug, message: message)
    }

    static func notice(_ message: String) {
        logMessage(level: .notice, message: message)
    }

    static func warning(_ message: String) {
        logMessage(level: .warning, message: message)
    }

    static func error(_ message: String) {
        logMessage(level: .error, message: message)
    }

    static func critical(_ message: String) {
        logMessage(level: .critical, message: message)
    }

    /// Local wall-clock time to the millisecond: a live trace is read
    /// for order and gaps. Same format as `log show` and `log stream`
    /// print, so a console line and a unified-log line read alike.
    ///
    /// Console only. The unified log stamps its own.
    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    /// The line a foreground run prints.
    ///
    /// No process name and no pid: they do not vary within a run.
    /// warning, error and critical keep their label, so they are
    /// findable by eye in a stream of traces.
    static func consoleLine(level: LogLevel, message: String, at time: Date = Date()) -> String {
        let stamp = timestampFormatter.string(from: time)
        switch level {
        case .info, .debug, .notice:
            return "\(stamp) \(message)"
        case .warning, .error, .critical:
            return "\(stamp) \(level.rawValue): \(message)"
        }
    }

    private static func logMessage(level: LogLevel, message: String) {
        if isConsoleEnabled {
            print(consoleLine(level: level, message: message))
            fflush(stdout)
            return
        }

        let ulsMessage = message

        switch level {
        case .info:
            logger.info("\(ulsMessage, privacy: .public)")
        case .notice:
            logger.log(level: .default, "\(ulsMessage, privacy: .public)")
        case .debug:
            logger.debug("\(ulsMessage, privacy: .public)")
        case .warning:
            logger.log(level: .default, "\(ulsMessage, privacy: .public)")
        case .error:
            logger.error("\(ulsMessage, privacy: .public)")
        case .critical:
            logger.fault("\(ulsMessage, privacy: .public)")
        }
    }
}
