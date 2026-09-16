import Foundation
import XCTest

@testable import cmd_key_happy

/// Reading a bundle's signing identity, and comparing two of them.
///
/// This is what `check-install` uses to refuse replacing an installed
/// bundle with one macOS will not accept for the registered agent, so
/// the comparison and the ad-hoc case both matter: an ad-hoc
/// signature names no team, and the launch requirement then falls
/// back to a code hash that changes on every build.
final class SigningIdentityTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
          .resolvingSymlinksInPath()
          .appendingPathComponent("ckh-signing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A minimal bundle, ad-hoc signed. Ad-hoc needs no certificate,
    /// so this works on a machine that has never had one.
    private func makeAdHocBundle(identifier: String) throws -> String {
        let bundle = root.appendingPathComponent("Probe.app")
        let macos = bundle.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
          at: URL(fileURLWithPath: "/bin/echo"),
          to: macos.appendingPathComponent("Probe"))
        let plist = """
          <?xml version="1.0" encoding="UTF-8"?>
          <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
          <plist version="1.0">
          <dict>
          \t<key>CFBundleIdentifier</key><string>\(identifier)</string>
          \t<key>CFBundleExecutable</key><string>Probe</string>
          \t<key>CFBundleName</key><string>Probe</string>
          </dict>
          </plist>
          """
        try plist.write(to: bundle.appendingPathComponent("Contents/Info.plist"),
                        atomically: true, encoding: .utf8)

        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", bundle.path]
        codesign.standardOutput = FileHandle.nullDevice
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        XCTAssertEqual(codesign.terminationStatus, 0, "codesign failed on the fixture")
        return bundle.path
    }

    // MARK: - reading a signature

    func testAdHocBundleReportsItsIdentifierAndNoTeam() throws {
        let bundle = try makeAdHocBundle(identifier: "com.example.probe")
        let identity = try signingIdentity(ofBundleAt: bundle)
        XCTAssertEqual(identity.signingIdentifier, "com.example.probe")
        XCTAssertNil(identity.teamIdentifier)
        XCTAssertTrue(identity.isAdHoc)
    }

    /// Unsigned is a distinct outcome from ad-hoc. Both report no
    /// team, so returning a placeholder identifier would make an
    /// unsigned bundle look ad-hoc to check-install.
    func testUnsignedFileIsRejectedAsUnsigned() throws {
        let plain = root.appendingPathComponent("plain.txt")
        try "hello\n".write(to: plain, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try signingIdentity(ofBundleAt: plain.path)) { error in
            guard case SigningIdentityError.unsigned(let path) = error else {
                return XCTFail("expected unsigned, got \(error)")
            }
            XCTAssertEqual(path, plain.path)
        }
    }

    func testUnsignedErrorDescriptionNamesThePath() {
        let description = SigningIdentityError.unsigned("/some/Bundle.app").errorDescription ?? ""
        XCTAssertTrue(description.contains("/some/Bundle.app"), "got: \(description)")
    }

    func testMissingPathIsRejected() {
        let missing = root.appendingPathComponent("nope.app").path
        XCTAssertThrowsError(try signingIdentity(ofBundleAt: missing)) { error in
            guard case SigningIdentityError.unreadable = error else {
                return XCTFail("expected unreadable, got \(error)")
            }
        }
    }

    /// The error has to name the path, since it reaches the user
    /// through make install and is the only clue to which bundle
    /// failed.
    func testErrorDescriptionNamesThePath() {
        let error = SigningIdentityError.unreadable("/some/Bundle.app", OSStatus(-67062))
        let description = error.errorDescription ?? ""
        XCTAssertTrue(description.contains("/some/Bundle.app"), "got: \(description)")
    }

    // MARK: - comparing identities

    func testIdentitiesWithTheSameTeamAndIdentifierAreEqual() {
        let a = SigningIdentity(teamIdentifier: "ABCDE12345", signingIdentifier: "com.example.app")
        let b = SigningIdentity(teamIdentifier: "ABCDE12345", signingIdentifier: "com.example.app")
        XCTAssertEqual(a, b)
    }

    /// The case check-install exists for: same bundle identifier,
    /// different team. Refusing only ad-hoc would let this through.
    func testDifferentTeamsAreNotEqual() {
        let a = SigningIdentity(teamIdentifier: "ABCDE12345", signingIdentifier: "com.example.app")
        let b = SigningIdentity(teamIdentifier: "ZZZZZ99999", signingIdentifier: "com.example.app")
        XCTAssertNotEqual(a, b)
    }

    func testAdHocIsNotEqualToTeamSigned() {
        let adHoc = SigningIdentity(teamIdentifier: nil, signingIdentifier: "com.example.app")
        let team = SigningIdentity(teamIdentifier: "ABCDE12345", signingIdentifier: "com.example.app")
        XCTAssertNotEqual(adHoc, team)
        XCTAssertTrue(adHoc.isAdHoc)
        XCTAssertFalse(team.isAdHoc)
    }

    func testDescriptionDistinguishesAdHocFromTeamSigned() {
        XCTAssertEqual(
          SigningIdentity(teamIdentifier: nil, signingIdentifier: "com.example.app").description,
          "com.example.app (ad-hoc)")
        XCTAssertEqual(
          SigningIdentity(teamIdentifier: "ABCDE12345", signingIdentifier: "com.example.app").description,
          "com.example.app (team ABCDE12345)")
    }
}
