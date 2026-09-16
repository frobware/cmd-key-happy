# Installation

cmd-key-happy installs as an application bundle (`CmdKeyHappy.app`)
containing a LaunchAgent, registered through `SMAppService`. The
Makefile is the source of truth; `swift build` on its own only gives
you a compile check, and skips the bundle assembly, metadata
injection, and codesigning that the daemon depends on.

## Upgrading from the old layout

Earlier versions installed a bare binary to `~/.local/bin` and a
hand-written plist to `~/Library/LaunchAgents`. Clear that install
before installing this one:

    $ make migrate-legacy

## Install

    $ make install
    $ make register

`make install` copies the bundle to `~/Applications` (override with
`INSTALL_DIR=/Applications`, which then uses sudo). `make register`
hands the embedded LaunchAgent to `SMAppService`, which starts it and
adds an entry under System Settings > General > Login Items.

`register` refuses to run from anywhere but `/Applications` or
`~/Applications`, so it cannot record a job pointing at your build
tree.

## Accessibility

cmd-key-happy needs the Accessibility permission to install its event
taps. Grant it to `CmdKeyHappy.app` under System Settings > Privacy &
Security > Accessibility. Until you do, the daemon exits non-zero and
launchd's `KeepAlive` retries it, so it comes up on its own once the
grant is given.

Set `CODESIGN_IDENTITY` in a `local.mk` (ignored by git) to sign with
a real Apple Development certificate:

    CODESIGN_IDENTITY = Apple Development: Your Name (TEAMID)

The Accessibility grant is keyed on the signature. The default is
ad-hoc signing, which changes on every build and so drops the grant
each time you rebuild.

Ad-hoc signing is fine until the agent is registered. At registration
macOS records a launch requirement for the label, and installing a
bundle that cannot satisfy it rewrites that requirement to a cdhash
no build matches. launchd then rejects the job with `EX_CONFIG`, and
neither `make unregister` nor re-registering clears it: only `make
uninstall`, which removes the bundle, makes macOS derive the
requirement afresh. `make install` refuses that combination rather
than letting it happen, so a missing `local.mk` stops the install
instead of breaking the installed agent.

If you reach that state anyway, the recovery is:

    $ make uninstall
    $ make install
    $ make register

## Your terminal must treat Option as Meta

Swapping the modifiers is only half of it. Your terminal also has to
send Option as Meta rather than composing a character, and on macOS
the default is to compose -- so Command-X gives you the Option+X
character rather than the `alt-x` your shell is waiting for.

Set `macos-option-as-alt` in Ghostty, `macos_option_as_alt` in kitty,
`option_as_alt` in Alacritty, or the
`send_composed_key_when_*_alt_is_pressed` pair in WezTerm. The README
has the values and the trade-off.

## Day to day

    $ make reload         # rebuild, reinstall, restart the agent
    $ make parse-config   # check the config file before reloading
    $ make state          # where it is installed, registered, running
    $ make stream-logs    # follow the log live
    $ make show-errors    # what went wrong in the last hour

`make help` lists everything.

## Uninstall

    $ make uninstall

That unregisters the agent, stops the daemon and removes the bundle,
in that order -- the agent has to be unregistered while the bundle
still exists, or SMAppService cannot resolve what it is unregistering.
Installing and uninstalling under `~/Applications` need no elevation;
only an `INSTALL_DIR` outside your home directory asks for sudo.

Three things it deliberately leaves behind.

Your configuration stays at `~/Library/Application
Support/com.frobware.cmd-key-happy/`, so reinstalling picks up the
same list of apps. Delete the directory by hand if you want a clean
slate.

`CmdKeyHappy.app` stays listed under System Settings > Privacy &
Security > Accessibility. Nothing can remove it for you: the TCC
database is protected by SIP, and the entry is keyed on a path rather
than a bundle identifier, so even `tccutil` cannot target it. Remove
it there if it bothers you.

macOS keeps its BackgroundTaskManagement records, flipped to
`disabled` rather than deleted -- one for the app and one for the
agent. `sudo sfltool dumpbtm` shows them. Reinstalling re-enables
them, because they carry the same signing identity. A record written
by a differently signed binary is not reusable: SMAppService adopts
it and launchd rejects the job with `EX_CONFIG`, which is why the
launchd label is not the bundle identifier.

Reinstalling does not cost you a fresh Accessibility grant. The grant
follows the code signature, so as long as `CODESIGN_IDENTITY` is a
real certificate rather than the ad-hoc default, uninstall and install
round-trips leave it intact.
