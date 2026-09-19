import Foundation
import Security

/// The parts of a bundle's code signature that decide whether launchd
/// will accept it for an already-registered job.
///
/// macOS records a launch requirement when the agent is registered,
/// naming the identity that signed the bundle at that moment. A build
/// that does not satisfy it is rejected with EX_CONFIG, and clearing
/// that takes an unregister and a register, so the cheap moment to
/// notice is before replacing the bundle.
struct SigningIdentity: Equatable {
    /// Absent for ad-hoc, and absent for a self-signed certificate
    /// too, so it cannot be what tells them apart.
    let teamIdentifier: String?
    let signingIdentifier: String

    /// Read from the code directory rather than inferred from a
    /// missing team. A self-signed certificate names no team and is
    /// still perfectly usable under a registration: the requirement
    /// names the certificate's leaf hash, which does not move when
    /// you rebuild. Ad-hoc has no certificate at all, so it falls
    /// back to a code hash, which does.
    let isAdHoc: Bool

    var description: String {
        if isAdHoc { return "\(signingIdentifier) (ad-hoc)" }
        guard let team = teamIdentifier else {
            return "\(signingIdentifier) (self-signed)"
        }
        return "\(signingIdentifier) (team \(team))"
    }
}

enum SigningIdentityError: Error, LocalizedError {
    case unreadable(String, OSStatus)
    case unsigned(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let path, let status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "\(path): cannot read code signature: \(detail)"
        case .unsigned(let path):
            return "\(path): not signed"
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

    // An unsigned bundle reports neither identifier nor team, which
    // would otherwise be indistinguishable from an ad-hoc signature.
    // They are not the same thing: ad-hoc names no team but is signed,
    // whereas this cannot satisfy any launch requirement at all.
    guard let identifier = info[kSecCodeInfoIdentifier as String] as? String else {
        throw SigningIdentityError.unsigned(path)
    }

    // The adhoc bit of the code directory flags, which is the only
    // honest answer. Absence of a team identifier is not: a
    // self-signed certificate has none either.
    let flags = info[kSecCodeInfoFlags as String] as? UInt32 ?? 0
    let adHoc = flags & SecCodeSignatureFlags.adhoc.rawValue != 0

    return SigningIdentity(
      teamIdentifier: info[kSecCodeInfoTeamIdentifier as String] as? String,
      signingIdentifier: identifier,
      isAdHoc: adHoc
    )
}
