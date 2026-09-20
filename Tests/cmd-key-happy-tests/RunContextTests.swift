import XCTest

@testable import cmd_key_happy

/// Whether anyone is there, and the three things that follow from it.
///
/// launchd passes --headless and a person does not, so the flag is the
/// whole of the evidence. What it decides is not one thing: where log
/// lines go, whether the accessibility check may prompt, and whether
/// the event trace starts on.
final class RunContextTests: XCTestCase {

    // MARK: - reading the command line

    func testNoFlagIsAttended() {
        XCTAssertEqual(RunContext(arguments: ["cmd-key-happy"]), .attended)
    }

    func testTheFlagIsUnattended() {
        XCTAssertEqual(RunContext(arguments: ["cmd-key-happy", "--headless"]), .unattended)
    }

    /// The agent plist passes a bare argv[0] and the flag after it,
    /// relying on the default subcommand; a person may name the
    /// subcommand and a config file as well.
    func testTheFlagIsFoundAmongstOtherArguments() {
        XCTAssertEqual(
          RunContext(arguments: ["cmd-key-happy", "run", "--config", "/tmp/config", "--headless"]),
          .unattended)
    }

    func testAnUnrelatedFlagIsAttended() {
        XCTAssertEqual(
          RunContext(arguments: ["cmd-key-happy", "run", "--parse-config"]),
          .attended)
    }

    // MARK: - what follows from it

    /// Under launchd stdio is /dev/null, so a printed line is lost.
    func testUnattendedLogsToTheUnifiedLog() {
        XCTAssertFalse(RunContext.unattended.logsToConsole)
    }

    func testAttendedLogsToTheConsole() {
        XCTAssertTrue(RunContext.attended.logsToConsole)
    }

    /// KeepAlive retries every few seconds without the grant, and each
    /// prompt would reopen System Settings.
    func testUnattendedDoesNotPrompt() {
        XCTAssertFalse(RunContext.unattended.promptsForAccessibility)
    }

    func testAttendedPrompts() {
        XCTAssertTrue(RunContext.attended.promptsForAccessibility)
    }

    /// A run someone is watching traces from the start; under launchd
    /// SIGUSR1 asks for it.
    func testUnattendedDoesNotTraceByDefault() {
        XCTAssertFalse(RunContext.unattended.tracesByDefault)
    }

    func testAttendedTracesByDefault() {
        XCTAssertTrue(RunContext.attended.tracesByDefault)
    }
}
