import XCTest

@testable import cmd_key_happy

/// What a foreground run prints.
///
/// A line carries what varies: the time, which a trace is read for.
/// The process name and pid do not vary within a run.
final class CKHLogTests: XCTestCase {
    private func line(_ level: CKHLog.LogLevel, _ message: String) -> String {
        CKHLog.consoleLine(level: level, message: message, at: Date(timeIntervalSince1970: 0))
    }

    /// Local time, read by someone sitting in front of it, so assert
    /// the shape rather than a value that depends on where the machine
    /// thinks it is.
    private func split(_ line: String) -> (stamp: String, rest: String) {
        let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
        return (parts[0] + " " + parts[1], parts.count > 2 ? parts[2] : "")
    }

    func testEveryLineIsStamped() {
        let (stamp, rest) = split(line(.info, "Event tap created"))
        XCTAssertNotNil(stamp.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}$"#,
                                    options: .regularExpression),
                        "not a timestamp: \(stamp)")
        XCTAssertEqual(rest, "Event tap created")
    }

    func testRoutineOutputIsOtherwiseJustTheMessage() {
        XCTAssertEqual(split(line(.info, "Event tap created")).rest, "Event tap created")
        XCTAssertEqual(split(line(.debug, "event=keyDown")).rest, "event=keyDown")
        XCTAssertEqual(split(line(.notice, "event=keyDown")).rest, "event=keyDown")
    }

    /// The levels that want attention keep their label: an error in a
    /// stream of traces has to be findable by eye.
    func testLevelsThatWantAttentionAreLabelled() {
        XCTAssertEqual(split(line(.warning, "config vanished")).rest, "warning: config vanished")
        XCTAssertEqual(split(line(.error, "tap disabled")).rest, "error: tap disabled")
        XCTAssertEqual(split(line(.critical, "unrecoverable")).rest, "critical: unrecoverable")
    }
}
