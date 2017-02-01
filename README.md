Swap cmd and alt (or command and option) keys in Mac OS X (macOS).

This program allows you to swap the command and alt (or option) keys in any application, but in particular Terminal.app. This can be extremely handy when ssh'ing into other UN*X boxes and running "emacs -nw". It also allows you to have the traditional readline navigation work properly when using Bash (i.e., alt-backspace, alt-f, alt-b, etc) in the Terminal.

The decision to swap the keys is based on a customizable script (Lua). This script allows you to exclude certain key combinations per application, or globally.  For example, "cmd-tab" is an exclusion in my Lua script regardless of which application is running, as I still want this key combination to cycle the active set of applications.  I have "cmd-c" and "cmd-v" as exclusions when the front most application is the Terminal -- these combinations are so universal that I find it easier to leave them as they are -- but all other key combinations involving the cmd key get swapped with alt.

The motivation for this program was the many years of hitting alt-<something> in Linux only to find that it does not generate the same behaviour in Terminal.app.  Having the ability to run "emacs -nw" from within Terminal.app is now useable!

Mavericks

If you upgrade to Mavericks you'll get the following error "failed to create event tap!" when cmd-key-happy starts.  The granularity of using the accessibility APIs which is what cmd-key-happy depends on is both different and now much finer.  To fix this please reread the INSTALL file.

Note (1 Feb 2017): I rewrote this in C++ (see cpp directory) some
years ago and it is probably the better implementation for newer
versions of macOS but I never promoted it as I have stopped using
macOS on a regular basis.
