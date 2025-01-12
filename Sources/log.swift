import Foundation
import os.log

struct CKHLog {
    private static let logger = Logger(subsystem: "com.frobware.ckh", category: "default")
    private static let isConsoleEnabled = !CommandLine.arguments.contains("--headless")
    private static let processID = ProcessInfo.processInfo.processIdentifier
    private static let processName = ProcessInfo.processInfo.processName

    enum LogLevel: String {
        case info, debug, warning, error, critical
    }

    static func info(_ message: String, file: String = #file, line: Int = #line) {
        logMessage(level: .info, message: message, file: file, line: line)
    }

    static func debug(_ message: String, file: String = #file, line: Int = #line) {
        logMessage(level: .debug, message: message, file: file, line: line)
    }

    static func warning(_ message: String, file: String = #file, line: Int = #line) {
        logMessage(level: .warning, message: message, file: file, line: line)
    }

    static func error(_ message: String, file: String = #file, line: Int = #line) {
        logMessage(level: .error, message: message, file: file, line: line)
    }

    static func critical(_ message: String, file: String = #file, line: Int = #line) {
        logMessage(level: .critical, message: message, file: file, line: line)
    }

   private static func logMessage(level: LogLevel, message: String, file: String, line: Int) {
       let filename = (file as NSString).lastPathComponent
       let fileLineInfo = level == .debug ? " (\(filename):\(line))" : ""

        if isConsoleEnabled {
            print("\(ProcessInfo.processInfo.processName)[\(ProcessInfo.processInfo.processIdentifier)]: \(level): \(message)\(fileLineInfo)")
            fflush(stdout)
            return
        }

        let ulsMessage = "\(message)\(fileLineInfo)"

        switch level {
        case .info:
            logger.info("\(ulsMessage, privacy: .public)")
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
