import XCTest

@testable import cmd_key_happy

/// The version the program calls itself.
///
/// Compiled in rather than injected: a binary run from `.build/debug`
/// has no Info.plist, and the whole point of the number is that it
/// answers in that case too. `make bundle` reads it back out of the
/// source to fill CFBundleShortVersionString, so the declaration has
/// to keep the shape the Makefile matches on.
final class BuildMetadataTests: XCTestCase {
    private func metadata() -> BuildMetadata {
        BuildMetadata(commitHash: "445cde4",
                      describe: "v1.0.0-47-g445cde4",
                      branch: "master",
                      buildDate: "2026-09-18T10:00:00Z",
                      bundleIdentifier: "com.frobware.cmd-key-happy",
                      bundlePath: "/Applications/CmdKeyHappy.app")
    }

    /// Leading with the version puts the answer to "which one is
    /// running" first, ahead of the checkout it was built from.
    func testTheBannerLeadsWithTheVersion() {
        XCTAssertEqual(metadata().shortLine,
                       "cmd-key-happy \(BuildMetadata.version)"
                         + " (master, v1.0.0-47-g445cde4) built 2026-09-18T10:00:00Z")
    }

    /// The Makefile matches on `static let version = "..."` to fill
    /// the bundled plist. A version that does not parse as one would
    /// reach the bundle unnoticed.
    func testTheVersionIsSemver() {
        let pattern = #"^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$"#
        XCTAssertNotNil(BuildMetadata.version.range(of: pattern, options: .regularExpression),
                        "not a version: \(BuildMetadata.version)")
    }
}
