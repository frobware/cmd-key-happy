# Installation

cmd-key-happy installs as an application bundle (`CmdKeyHappy.app`)
containing a LaunchAgent, registered through `SMAppService`. The
Makefile is the source of truth; `swift build` on its own only gives
you a compile check, and skips the bundle assembly, metadata
injection, and codesigning that the daemon depends on.

## What you need

macOS 13 or later and a Swift 6 toolchain. The Xcode command-line
tools are enough to build and install:

    $ xcode-select --install

Full Xcode is needed only if you want a signing certificate, which the
next section covers.

Then:

    $ git clone https://github.com/frobware/cmd-key-happy.git
    $ cd cmd-key-happy

## Upgrading from the old layout

Earlier versions installed a bare binary to `~/.local/bin` and a
hand-written plist to `~/Library/LaunchAgents`. Clear that install
before installing this one:

    $ make migrate-legacy

## Settle the signing identity before you install

Two things are keyed on the bundle's code signature: the Accessibility
permission you are about to grant, and the launch requirement macOS
records when the agent is registered. Both are decided by the first
install, so choose the identity now rather than after.

The default is ad-hoc signing, which needs no Apple Developer
certificate. It changes on every build, so every rebuild costs you the
Accessibility grant again. A real certificate takes a few minutes to
get and spares you that.

### Getting a certificate

A local development certificate is all you need. The bundle never
leaves your machine, so there is nothing to distribute and nothing to
notarise: no Developer ID, no paid Developer Program. A free Apple ID
gives you a personal team, and that is enough.

In Xcode: Settings > Accounts, add your Apple ID, select the team it
appears under (a free account shows as "Your Name (Personal Team)"),
then Manage Certificates... > + > Apple Development. The certificate
and its private key land in your login keychain.

Ask the keychain for the exact string rather than typing it out:

    $ security find-identity -v -p codesigning
      1) 5A0F... "Apple Development: Your Name (TEAMID)"
         1 valid identities found

Put what is inside the quotes, without the quotes, in a `local.mk` at
the repo root. That file is ignored by git, so your identity stays out
of the repository:

    CODESIGN_IDENTITY = Apple Development: Your Name (TEAMID)

`make bundle` echoes the identity it signs with, so you can see at a
glance whether `local.mk` was picked up.

### Changing it later

`make install` refuses to replace an installed bundle with one signed
by a different identity, in either direction -- ad-hoc over a
certificate, a certificate over ad-hoc, or one certificate over
another. It also refuses an ad-hoc build whenever the agent is
registered, whether or not a bundle is still installed: every ad-hoc
build has a different code hash, so there is no such thing as
replacing one with another.

That last one decides how far you get without a certificate. Ad-hoc,
`make reload` works exactly once -- it installs and registers -- and
every one after that stops at the check, until `make uninstall` clears
the recorded requirement. Settling the identity first is not advice.

That is not obstinacy. macOS recorded the installed identity for the
agent's label, and a build that cannot satisfy the recorded
requirement rewrites it to a code hash nothing matches; launchd then
rejects the job with `EX_CONFIG`. Neither `make unregister` nor
re-registering clears that. Only `make uninstall`, which removes the
bundle, makes macOS derive the requirement afresh.

So changing your mind later is recoverable, just tedious -- and this
is the same sequence that recovers a job already stuck in `EX_CONFIG`:

    $ make uninstall
    $ make install
    $ make register

## Install

    $ make install
    $ make register

`make install` builds the bundle and copies it to `~/Applications`
(override with `INSTALL_DIR=/Applications`, which then uses sudo).
`make register` hands the embedded LaunchAgent to `SMAppService`,
which starts it and adds an entry under System Settings > General >
Login Items.

`register` refuses to run from anywhere but `/Applications` or
`~/Applications`, so it cannot record a job pointing at your build
tree.

## Accessibility

cmd-key-happy needs the Accessibility permission to install its event
taps. Grant it to `CmdKeyHappy.app` under System Settings > Privacy &
Security > Accessibility. Until you do, the daemon exits non-zero and
launchd's `KeepAlive` retries it, so it comes up on its own once the
grant is given.

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
    $ make stop           # stop the agent until you start it again
    $ make parse-config   # check the config file before reloading
    $ make state          # where it is installed, registered, running
    $ make stream-logs    # follow the log live
    $ make show-errors    # what went wrong in the last hour

`make reload` kickstarts the job that is already there rather than
creating one, so it needs the agent registered; if it is not, run
`make install && make register` instead. `make stop` boots the job out
and leaves the registration alone, so `make register` starts it again,
as does logging in again; it builds and installs nothing, so it still
works when the build tree does not.

`make help` lists everything.

## Watching what it does to a keystroke

The daemon can report every event a tapped application receives,
saying what arrived and what was delivered. Started by hand it does
that already:

    $ make run

Under launchd it stays quiet until you ask, since it is a line per
keystroke:

    $ make trace          # tell the running daemon to start; again to stop
    $ make stream-logs    # recent context, then live, in an untapped window
    $ make show-logs      # or read it back afterwards

Nothing else has to be enabled, and none of it needs `sudo`. Watch
from a window that is not one of the applications in your config, or
you will be reading your own typing reflected back at you.

    Ghostty[70550] event=keyDown      action=swap     key=3 modifiers.in=cmd(L) modifiers.out=opt(L)
    Ghostty[70550] event=flagsChanged action=relabel  key.in=L-cmd key.out=L-opt modifiers=none

`action` is what was decided: `swap` for a key press, `relabel` for
the modifier keys themselves, `passthrough` for a chord deliberately
left alone. `cmd(L)` is the left command key -- the modifier and the
side it came from, which applications read separately. A field split
into `.in` and `.out` is one that changed.

## Uninstall

    $ make uninstall

That stops the daemon, unregisters the agent, and removes the bundle,
in that order. Stopping first matters because a job launchd has
refused to spawn can outlive unregistering, and removing the bundle
from under a job that is still loaded is what leaves the recorded
launch requirement in a state nothing can satisfy. Unregistering has
to happen while the bundle still exists, or `SMAppService` cannot
resolve what it is unregistering.

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
`disabled` rather than deleted. `sudo sfltool dumpbtm` shows them.
Reinstalling re-enables them, because they carry the same signing
identity. A record written by a differently signed binary is not
reusable: SMAppService adopts it and launchd rejects the job with
`EX_CONFIG`, which is why the launchd label is not the bundle
identifier.

The Accessibility grant follows the code signature rather than the
bundle, so an uninstall and install round-trip with the same real
certificate presents macOS with an unchanged signature. Whether it
keeps the grant across the removal itself is something we have not
measured; with the ad-hoc default the signature changes anyway, so
the grant will not survive.
