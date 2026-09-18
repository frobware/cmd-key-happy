import XCTest

@testable import cmd_key_happy

/// Which taps a configuration change actually calls for.
///
/// Tearing every tap down and building them all again would drop
/// swapping for every application for a window, and rebuild taps macOS
/// is perfectly happy with. Most changes call for nothing at all.
final class TapPlanTests: XCTestCase {
    private let ghostty = RunningApp(pid: 100, name: "Ghostty")
    private let alacritty = RunningApp(pid: 200, name: "Alacritty")
    private let mail = RunningApp(pid: 300, name: "Mail")

    func testReloadingAnUnchangedConfigurationDoesNothing() {
        let plan = tapPlan(desired: ["Ghostty", "Alacritty"],
                           running: [ghostty, alacritty, mail],
                           tapped: [100, 200])
        XCTAssertEqual(plan, TapPlan(create: [], remove: []))
    }

    func testAddingANameCreatesOneTap() {
        let plan = tapPlan(desired: ["Ghostty", "Alacritty"],
                           running: [ghostty, alacritty, mail],
                           tapped: [100])
        XCTAssertEqual(plan, TapPlan(create: [alacritty], remove: []))
    }

    func testRemovingANameRemovesOneTap() {
        let plan = tapPlan(desired: ["Ghostty"],
                           running: [ghostty, alacritty, mail],
                           tapped: [100, 200])
        XCTAssertEqual(plan, TapPlan(create: [], remove: [200]))
    }

    /// Configured but not running is the ordinary case for most of a
    /// list: the workspace notification taps it when it launches.
    func testAnApplicationThatIsNotRunningYieldsNothing() {
        let plan = tapPlan(desired: ["Ghostty", "kitty"],
                           running: [ghostty],
                           tapped: [100])
        XCTAssertEqual(plan, TapPlan(create: [], remove: []))
    }

    /// A tapped process that has exited without us hearing about it.
    func testATappedApplicationThatHasGoneIsRemoved() {
        let plan = tapPlan(desired: ["Ghostty", "Alacritty"],
                           running: [ghostty],
                           tapped: [100, 200])
        XCTAssertEqual(plan, TapPlan(create: [], remove: [200]))
    }

    /// Two windows of the same application are two processes, and each
    /// needs its own tap.
    func testEveryProcessOfAConfiguredApplicationIsTapped() {
        let second = RunningApp(pid: 101, name: "Ghostty")
        let plan = tapPlan(desired: ["Ghostty"],
                           running: [ghostty, second],
                           tapped: [])
        XCTAssertEqual(plan, TapPlan(create: [ghostty, second], remove: []))
    }

    func testEverythingGoesWhenTheConfigurationEmpties() {
        let plan = tapPlan(desired: [],
                           running: [ghostty, alacritty],
                           tapped: [100, 200])
        XCTAssertEqual(plan, TapPlan(create: [], remove: [100, 200]))
    }
}
