import Darwin

/// One process that is running now.
struct RunningApp: Equatable {
    let pid: pid_t
    let name: String
}

/// The taps a configuration calls for, against the ones that exist.
struct TapPlan: Equatable {
    /// Processes to tap that are not tapped yet.
    let create: [RunningApp]
    /// Taps to tear down, because the application left the
    /// configuration or the process has gone.
    let remove: [pid_t]
}

/// Work out what a configuration change calls for, which is usually
/// nothing, or one tap.
///
/// Each process is its own tap, so two windows of the same application
/// are two entries: the name decides whether a process is wanted, the
/// pid decides whether it already has one.
func tapPlan(desired: Set<String>,
             running: [RunningApp],
             tapped: Set<pid_t>) -> TapPlan {
    let wanted = running.filter { desired.contains($0.name) }
    let wantedPIDs = Set(wanted.map { $0.pid })

    return TapPlan(
      create: wanted.filter { !tapped.contains($0.pid) },
      // Sorted so the plan is a value, not an accident of hashing.
      remove: tapped.subtracting(wantedPIDs).sorted())
}
