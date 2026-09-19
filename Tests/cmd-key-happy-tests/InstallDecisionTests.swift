import XCTest

@testable import cmd_key_happy

/// Whether replacing the installed bundle would leave an agent macOS
/// refuses to start.
///
/// Comparing the two signing identities is not the whole test. Two
/// ad-hoc builds carry the same identifier and no team, so they
/// compare equal, while the recorded launch requirement names a code
/// hash that differs on every build.
final class InstallDecisionTests: XCTestCase {
    private let team = SigningIdentity(teamIdentifier: "ABCDE12345", signingIdentifier: "com.frobware.cmd-key-happy", isAdHoc: false)
    private let otherTeam = SigningIdentity(teamIdentifier: "ZZZZZ99999", signingIdentifier: "com.frobware.cmd-key-happy", isAdHoc: false)
    private let adHoc = SigningIdentity(teamIdentifier: nil, signingIdentifier: "com.frobware.cmd-key-happy", isAdHoc: true)
    private let selfSigned = SigningIdentity(teamIdentifier: nil, signingIdentifier: "com.frobware.cmd-key-happy", isAdHoc: false)

    // MARK: - the identity changing

    func testSameTeamSignedIdentityIsAllowed() {
        XCTAssertEqual(
          installDecision(candidate: team, installed: team, isRegistered: true),
          .allowed)
    }

    func testADifferentTeamIsRefused() {
        XCTAssertEqual(
          installDecision(candidate: team, installed: otherTeam, isRegistered: true),
          .identityChanged(installed: otherTeam, candidate: team))
    }

    func testTeamSignedOverAdHocIsRefused() {
        XCTAssertEqual(
          installDecision(candidate: team, installed: adHoc, isRegistered: true),
          .identityChanged(installed: adHoc, candidate: team))
    }

    // MARK: - ad-hoc against a registration

    /// Both sides ad-hoc, so the identities compare equal while the
    /// code hash the requirement actually names differs on every
    /// build. This is precisely the install that breaks the agent.
    func testAdHocOverAnAdHocInstallIsRefusedWhenRegistered() {
        XCTAssertEqual(
          installDecision(candidate: adHoc, installed: adHoc, isRegistered: true),
          .adHocOverRegistration)
    }

    func testAdHocOverAnAdHocInstallIsAllowedWhenNotRegistered() {
        XCTAssertEqual(
          installDecision(candidate: adHoc, installed: adHoc, isRegistered: false),
          .allowed)
    }

    func testAdHocWithNothingInstalledIsRefusedWhenRegistered() {
        XCTAssertEqual(
          installDecision(candidate: adHoc, installed: nil, isRegistered: true),
          .adHocOverRegistration)
    }

    func testAdHocWithNothingInstalledIsAllowedWhenNotRegistered() {
        XCTAssertEqual(
          installDecision(candidate: adHoc, installed: nil, isRegistered: false),
          .allowed)
    }

    /// A registration outliving the bundle is the case the first
    /// install after an uninstall meets, and a real certificate
    /// satisfies what it recorded.
    func testTeamSignedWithNothingInstalledIsAllowed() {
        XCTAssertEqual(
          installDecision(candidate: team, installed: nil, isRegistered: true),
          .allowed)
    }

    /// A self-signed certificate names no team but produces a
    /// requirement naming its leaf hash, so it is as installable over
    /// a registration as a team-signed build. Refusing it was a real
    /// bug: a fresh machine set up with `make signing-identity` could
    /// not install what it had just built.
    func testSelfSignedMayBeInstalledOverARegistration() {
        XCTAssertEqual(installDecision(candidate: selfSigned, installed: nil, isRegistered: true),
                       .allowed)
        XCTAssertEqual(installDecision(candidate: selfSigned, installed: selfSigned, isRegistered: true),
                       .allowed)
    }
}
