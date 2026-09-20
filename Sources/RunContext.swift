/// Whether anyone is there to read what this run prints.
///
/// Three things turn on the answer -- where log lines go, whether the
/// accessibility check may prompt, and whether the event trace starts
/// on -- and all three follow from the same absence, so it is decided
/// once, here.
///
/// The evidence is the --headless flag in the agent plist.
/// DaemonCommand declares it so the parser accepts and documents it,
/// but the answer is wanted before the command line is parsed: a parse
/// failure under launchd still has to reach the unified log. So the
/// arguments are read directly and `current` is what everything else
/// asks.
enum RunContext: Equatable {
    /// Started by hand, with a terminal to print to and someone
    /// reading it.
    case attended
    /// Started by launchd. stdio is /dev/null and nothing here can
    /// answer a dialog.
    case unattended

    /// What launchd passes and a person does not.
    static let headlessFlag = "--headless"

    /// This process, decided once from its own command line.
    static let current = RunContext(arguments: CommandLine.arguments)

    init(arguments: [String]) {
        self = arguments.contains(Self.headlessFlag) ? .unattended : .attended
    }

    /// Log lines are printed rather than written to the unified log.
    var logsToConsole: Bool { self == .attended }

    /// The accessibility check may ask macOS to open the settings
    /// pane. KeepAlive retries every few seconds until the grant is
    /// given, so unattended each attempt would reopen System Settings.
    var promptsForAccessibility: Bool { self == .attended }

    /// The event trace starts on, because someone asked for this run
    /// and is watching it. Unattended, SIGUSR1 asks for it.
    var tracesByDefault: Bool { self == .attended }
}
