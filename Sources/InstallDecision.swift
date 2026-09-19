/// Whether installing this bundle over what is there now would leave
/// an agent macOS will not start.
enum InstallDecision: Equatable {
    /// Nothing recorded for the label stands in the way.
    case allowed
    /// A different identity signed the installed bundle, and that is
    /// the one macOS recorded for the label.
    case identityChanged(installed: SigningIdentity, candidate: SigningIdentity)
    /// Ad-hoc, with a registration already recorded. Nothing signed
    /// ad-hoc can satisfy what that registration named, because with
    /// no certificate the requirement is a code hash that changes
    /// with every build.
    case adHocOverRegistration
}

/// Decide whether the candidate bundle may replace the installed one.
///
/// Two questions, not one. Comparing the identities answers the first:
/// a build signed by someone else cannot satisfy a requirement naming
/// the installed signer. Equal identities do not answer the second,
/// because two ad-hoc builds compare equal -- ad-hoc names no team, so
/// there is nothing left to compare but the bundle identifier, which
/// never changes. With no certificate, the requirement falls back to
/// a code hash, and that differs on every build. So the registration
/// is always the second half of the answer, whether or not a bundle is
/// installed.
///
/// A self-signed certificate also names no team, and is allowed: its
/// requirement names the certificate rather than a code hash.
func installDecision(candidate: SigningIdentity,
                     installed: SigningIdentity?,
                     isRegistered: Bool) -> InstallDecision {
    if let installed, installed != candidate {
        return .identityChanged(installed: installed, candidate: candidate)
    }
    if candidate.isAdHoc && isRegistered {
        return .adHocOverRegistration
    }
    return .allowed
}
