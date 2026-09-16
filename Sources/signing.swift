import Foundation
import Security

/// The parts of a bundle's code signature that decide whether launchd
/// will accept it for an already-registered job.
///
/// macOS records a launch requirement when the agent is registered,
/// naming the identity that signed the bundle at that moment. A build
/// that does not satisfy it is rejected with EX_CONFIG, and only a
/// full uninstall makes macOS derive the requirement afresh, so the
/// cheap moment to notice is before replacing the bundle.
struct SigningIdentity: Equatable {
    /// Absent for an ad-hoc signature, which is what makes ad-hoc
    /// unusable for a registered agent: with no team to name, the
    /// requirement falls back to a code hash that changes every build.
    let teamIdentifier: String?
    let signingIdentifier: String

    var isAdHoc: Bool { teamIdentifier == nil }

    var description: String {
        guard let team = teamIdentifier else {
            return "\(signingIdentifier) (ad-hoc)"
        }
        return "\(signingIdentifier) (team \(team))"
    }
}

enum SigningIdentityError: Error, LocalizedError {
    case unreadable(String, OSStatus)

    var errorDescription: String? {
        switch self {
        case .unreadable(let path, let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "\(path): cannot read code signature: \(detail)"
        }
    }
}

/// Read the signing identity of the bundle at `path`.
///
/// Uses the Security framework rather than parsing `codesign -dv`,
/// so the team identifier arrives as a value rather than as a line of
/// output that has to be matched.
func signingIdentity(ofBundleAt path: String) throws -> SigningIdentity {
    var staticCode: SecStaticCode?
    let createStatus = SecStaticCodeCreateWithPath(
      URL(fileURLWithPath: path) as CFURL, [], &staticCode)
    guard createStatus == errSecSuccess, let code = staticCode else {
        throw SigningIdentityError.unreadable(path, createStatus)
    }

    var information: CFDictionary?
    let infoStatus = SecCodeCopySigningInformation(
      code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
    guard infoStatus == errSecSuccess,
          let info = information as? [String: Any] else {
        throw SigningIdentityError.unreadable(path, infoStatus)
    }

    return SigningIdentity(
      teamIdentifier: info[kSecCodeInfoTeamIdentifier as String] as? String,
      signingIdentifier: info[kSecCodeInfoIdentifier as String] as? String ?? "unknown"
    )
}
