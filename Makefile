# Copyright (c) 2009, 2010, 2013, 2025 Andrew McDermott
#
# Source can be cloned from:
#
#	https://github.com/frobware/cmd-key-happy.git
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

APP_NAME    = cmd-key-happy
BUNDLE_NAME = CmdKeyHappy.app
BUNDLE_ID   = com.frobware.cmd-key-happy
ICON_NAME   = CmdKeyHappy
# Distinct from $(BUNDLE_ID). BackgroundTaskManagement keeps a record
# keyed on a launchd label permanently, and a record written by a
# differently signed binary cannot be reused: launchd rejects the job
# with EX_CONFIG. See the comment in the agent plist.
AGENT_LABEL = com.frobware.cmd-key-happy.agent
AGENT_PLIST = $(AGENT_LABEL).plist

# The os_log subsystem the daemon writes to; see Sources/log.swift,
# which must agree.
LOG_SUBSYSTEM = $(BUNDLE_ID)

# Build mode: debug or release (default: release).
BUILD_MODE ?= release
BUILD_DIR   = .build

# The bundle is assembled inside .build so it is already covered by
# .gitignore and cannot be mistaken for the installed copy.
BUNDLE_DIR = $(BUILD_DIR)/$(BUNDLE_NAME)

# Install location. Defaults to ~/Applications, which macOS treats
# identically to /Applications for SMAppService and TCC. Override with
# `make install INSTALL_DIR=/Applications` for the system-wide
# location, which then uses sudo automatically.
INSTALL_DIR ?= $(HOME)/Applications

# CODESIGN_IDENTITY defaults to ad-hoc signing so a fresh checkout
# builds without an Apple Developer certificate. Override with your
# identity in a repo-ignored local.mk -- a stable signature keeps the
# accessibility (TCC) grant valid across rebuilds, whereas an ad-hoc
# signature changes every build and invalidates it.
CODESIGN_IDENTITY ?= -

# Optional per-developer overrides (CODESIGN_IDENTITY, INSTALL_DIR,
# whatever else). Kept out of version control by .gitignore. Read
# before anything is derived from those variables.
-include local.mk

# Use sudo only when installing outside the user's home directory.
# ~/Applications is user-owned and needs no elevation; /Applications
# requires sudo for write access. Conditionals are evaluated where
# they appear, so this has to follow local.mk rather than precede it.
ifeq (,$(findstring $(HOME),$(INSTALL_DIR)))
SUDO = sudo
else
SUDO =
endif

# Pin every external binary to its absolute system path so a
# Nix-managed (or otherwise PATH-shadowed) duplicate cannot be picked
# up in place of the system one. GNU and BSD builds of the same tool
# differ in the flags used below.
SWIFT      = /usr/bin/swift
GIT        = /usr/bin/git
CODESIGN   = /usr/bin/codesign
PLISTBUDDY = /usr/libexec/PlistBuddy
PLUTIL     = /usr/bin/plutil
SIPS       = /usr/bin/sips
ICONUTIL   = /usr/bin/iconutil
LAUNCHCTL  = /bin/launchctl
LOG        = /usr/bin/log
PKILL      = /usr/bin/pkill
PGREP      = /usr/bin/pgrep
OPEN       = /usr/bin/open
SED        = /usr/bin/sed
AWK        = /usr/bin/awk
LS         = /bin/ls
MKDIR      = /bin/mkdir
CP         = /bin/cp
RM         = /bin/rm -f
DATE       = /bin/date

SWIFT_BIN_DIR = $(BUILD_DIR)/$(BUILD_MODE)

.PHONY: all
all: bundle

# Build the Swift package. A quick compile check; the bundle target is
# the source of truth for anything runnable.
.PHONY: build
build: ## [plumbing] Build the Swift package
	$(SWIFT) build -c $(BUILD_MODE)

# Drop a Spotlight opt-out marker into .build so the bundle assembled
# there is never indexed and cannot be reported as a second installed
# copy.
define prep_build_dir
	@$(MKDIR) -p $(BUILD_DIR)
	@if [ ! -f $(BUILD_DIR)/.metadata_never_index ]; then \
		: > $(BUILD_DIR)/.metadata_never_index; \
	fi
endef

# The icon is drawn by the binary rather than stored, so there is one
# source for it and no binary blob in the tree. iconutil wants every
# size present in the iconset, and sips derives them from the 1024px
# master the binary emits.
ICNS = $(BUILD_DIR)/$(ICON_NAME).icns
ICONSET = $(BUILD_DIR)/$(ICON_NAME).iconset

$(ICNS): build Sources/Icon.swift
	@echo "Rendering $(ICON_NAME).icns..."
	$(RM) -r $(ICONSET) $(ICNS)
	$(MKDIR) -p $(ICONSET)
	$(SWIFT_BIN_DIR)/$(APP_NAME) write-icon $(ICONSET)/icon_512x512@2x.png
	@for spec in 16:icon_16x16 32:icon_16x16@2x 32:icon_32x32 64:icon_32x32@2x \
	             128:icon_128x128 256:icon_128x128@2x 256:icon_256x256 \
	             512:icon_256x256@2x 512:icon_512x512; do \
		px=$${spec%%:*}; name=$${spec#*:}; \
		$(SIPS) -z $$px $$px $(ICONSET)/icon_512x512@2x.png \
			--out $(ICONSET)/$$name.png >/dev/null; \
	done
	$(ICONUTIL) -c icns $(ICONSET) -o $(ICNS)
	$(RM) -r $(ICONSET)

# Bundle skeleton. The bundle is rebuilt from scratch every time,
# since copying into an existing one leaves stale files behind.
# Info.plist and the LaunchAgent plist
# that SMAppService registers. Both plists live as real files at the
# repo root so they are editable without Makefile escaping. The agent
# plist uses BundleProgram (a bundle-relative executable path), so
# there is no install path to substitute and the same bytes work
# wherever the bundle lands.
define create_bundle_dirs
	@echo "Creating application bundle..."
	$(RM) -r $(BUNDLE_DIR)
	$(MKDIR) -p $(BUNDLE_DIR)/Contents/MacOS
	$(MKDIR) -p $(BUNDLE_DIR)/Contents/Resources
	$(MKDIR) -p $(BUNDLE_DIR)/Contents/Library/LaunchAgents
	$(CP) Info.plist $(BUNDLE_DIR)/Contents/Info.plist
	$(CP) $(AGENT_PLIST) $(BUNDLE_DIR)/Contents/Library/LaunchAgents/$(AGENT_PLIST)
	$(CP) $(ICNS) $(BUNDLE_DIR)/Contents/Resources/$(ICON_NAME).icns
endef

# Inject build metadata into the bundled Info.plist so the running
# daemon can self-report git commit, branch, describe, and build date.
# We inject into the *bundled* plist, not the repo one, so the source
# tree stays clean. Must run BEFORE codesign_bundle: modifying
# Info.plist after signing invalidates the signature.
define inject_metadata
	@PLIST=$(BUNDLE_DIR)/Contents/Info.plist; \
	GIT_SHA=$$($(GIT) rev-parse --short HEAD 2>/dev/null || echo unknown); \
	GIT_DESCRIBE=$$($(GIT) describe --always --dirty 2>/dev/null || echo unknown); \
	GIT_BRANCH=$$($(GIT) branch --show-current 2>/dev/null || echo unknown); \
	BUILD_DATE=$$($(DATE) -u +"%Y-%m-%dT%H:%M:%SZ"); \
	echo "Injecting metadata: $$GIT_DESCRIBE ($$GIT_BRANCH) built $$BUILD_DATE"; \
	for kv in \
		"GitCommitHash:$$GIT_SHA" \
		"GitDescribe:$$GIT_DESCRIBE" \
		"GitBranch:$$GIT_BRANCH" \
		"BuildDate:$$BUILD_DATE"; \
	do \
		key=$${kv%%:*}; val=$${kv#*:}; \
		$(PLISTBUDDY) -c "Add :$$key string $$val" $$PLIST 2>/dev/null || \
			$(PLISTBUDDY) -c "Set :$$key $$val" $$PLIST; \
	done
endef

# Sign the bundle with the configured identity. --deep re-signs any
# embedded resources; --force overwrites a prior signature. The TCC
# accessibility grant is keyed on this signature, so a stable identity
# from local.mk is what stops the grant resetting on every rebuild.
define codesign_bundle
	@echo "Signing $(BUNDLE_DIR) ($(CODESIGN_IDENTITY))..."
	$(CODESIGN) --force --deep --sign "$(CODESIGN_IDENTITY)" $(BUNDLE_DIR)
endef

# Assemble the bundle with a copied executable. We copy rather than
# symlink because codesign refuses bundles whose main executable is a
# symlink ("the main executable or Info.plist must be a regular file
# (no symlinks, etc.)").
.PHONY: bundle
bundle: build $(ICNS) ## [plumbing] Build, assemble, inject metadata and sign CmdKeyHappy.app (default)
	$(call prep_build_dir)
	$(call create_bundle_dirs)
	$(CP) $(SWIFT_BIN_DIR)/$(APP_NAME) $(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME)
	$(call inject_metadata)
	$(call codesign_bundle)
	@echo "Bundle created at $(BUNDLE_DIR)"

INSTALLED_BUNDLE = $(INSTALL_DIR)/$(BUNDLE_NAME)
INSTALLED_BIN    = $(INSTALLED_BUNDLE)/Contents/MacOS/$(APP_NAME)

# Refuse to install an ad-hoc signed bundle over a registered agent.
# macOS records a launch requirement for the label at registration;
# a bundle that cannot satisfy it rewrites that requirement to a
# cdhash no build matches, and launchd then rejects the job with
# EX_CONFIG. Ad-hoc signing is fine on its own, so this tests for the
# combination rather than for the identity.
#
# Refuse to replace the installed bundle with one macOS will not
# accept for the registered agent. The comparison lives in the binary
# we have just built, which reads both signatures through the Security
# framework and knows its own bundle path; the Makefile only has to
# say which bundle would be replaced.
define check_signing_identity
	@$(BUNDLE_DIR)/Contents/MacOS/$(APP_NAME) check-install "$(INSTALLED_BUNDLE)"
endef

# Install the bundle to $(INSTALL_DIR). SMAppService resolves the
# registered job through the bundle it was registered from, so the
# install location must be stable -- which is why `register` refuses
# to run from the build tree.
.PHONY: install
install: bundle ## [install] Install the bundle to INSTALL_DIR (default ~/Applications)
	$(call check_signing_identity)
	@echo "Installing $(BUNDLE_NAME) to $(INSTALL_DIR)..."
	$(SUDO) $(MKDIR) -p "$(INSTALL_DIR)"
	$(SUDO) $(RM) -r "$(INSTALLED_BUNDLE)"
	$(SUDO) $(CP) -R $(BUNDLE_DIR) "$(INSTALL_DIR)/"
	@echo "Installed $(BUNDLE_NAME) to $(INSTALL_DIR)"

# Login-item management: register / unregister / status always target
# the installed bundle, so there is no way to accidentally register a
# job pointing at the build tree. The subcommand inside cmd-key-happy
# refuses to register from a non-installed bundle path as well.
# Did it start, and stay started?
#
# launchd's own state, not pgrep: launchd spawns the daemon even
# without the Accessibility permission and it exits a moment later, so
# a glimpsed process proves nothing. Nor does one glimpse of "running",
# hence the second look half a second on.
#
# Registered but not running is what a missing permission looks like.
# The daemon runs headless, so it cannot prompt; it exits non-zero and
# KeepAlive restarts it every few seconds.
define report_whether_running
	@n=0; STATE=""; \
	while [ $$n -lt 15 ]; do \
		STATE=$$($(LAUNCHCTL) print gui/$(shell id -u)/$(AGENT_LABEL) 2>/dev/null \
			| $(SED) -nE 's/^	state = //p'); \
		if [ "$$STATE" = "running" ]; then \
			sleep 0.5; \
			STATE=$$($(LAUNCHCTL) print gui/$(shell id -u)/$(AGENT_LABEL) 2>/dev/null \
				| $(SED) -nE 's/^	state = //p'); \
			if [ "$$STATE" = "running" ]; then break; fi; \
		fi; \
		n=$$((n+1)); \
		sleep 0.2; \
	done; \
	if [ "$$STATE" = "running" ]; then \
		echo "Follow along with: make stream-logs"; \
	else \
		echo ""; \
		echo "$(AGENT_LABEL) is registered but is not running."; \
		echo "Almost always this is the Accessibility permission, which launchd"; \
		echo "cannot ask for on your behalf: the daemon runs headless, so it"; \
		echo "exits instead of prompting."; \
		echo ""; \
		echo "  Switch on $(BUNDLE_NAME) under Privacy & Security > Accessibility."; \
		echo "  It lists itself there, unchecked, as soon as the daemon asks."; \
		echo ""; \
		echo "Switch it on and launchd starts the daemon within a few seconds."; \
		echo "Nothing here needs running again. Opening that pane now."; \
		echo ""; \
		echo "If it still does not start, make show-errors says why."; \
		$(OPEN) "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"; \
	fi
endef

# Talking to the installed copy requires it to be there. unregister is
# where this bites: a registration outlives the bundle that made it.
define require_installed
	@if [ ! -x "$(INSTALLED_BIN)" ]; then \
		echo "$(BUNDLE_NAME) is not installed in $(INSTALL_DIR)."; \
		echo "Install it with: make install"; \
		exit 1; \
	fi
endef

.PHONY: register
register: ## [install] Register the bundled LaunchAgent via SMAppService
	$(call require_installed)
	"$(INSTALLED_BIN)" register
	$(call report_whether_running)

.PHONY: unregister
unregister: ## [install] Unregister the LaunchAgent
	$(call require_installed)
	"$(INSTALLED_BIN)" unregister

.PHONY: status
status: ## [check] Print SMAppService registration status
	$(call require_installed)
	"$(INSTALLED_BIN)" status

.PHONY: version
version: ## [check] Print build metadata for the installed bundle
	$(call require_installed)
	"$(INSTALLED_BIN)" version

# Check the configuration file is present and readable without
# starting the daemon. Those are the conditions the daemon exits on,
# so catching them here beats a job that fails on start and is
# restarted in a loop by KeepAlive. There is no grammar to check:
# every non-empty line is an app name, and a name matching no running
# application is simply never tapped.
.PHONY: parse-config
parse-config: ## [check] Validate the config file without starting the daemon
	$(call require_installed)
	"$(INSTALLED_BIN)" --parse-config

# Inner-loop iteration: rebuild, reinstall, and bounce the agent so
# the new binary is picked up. kickstart -k kills the running job and
# restarts it in one step; the job must already be registered.
# Put the new build in place and get it running, from whatever state
# the machine is in.
#
# kickstart restarts a loaded job and fails when there is none, so a
# machine that has never registered falls through to registering.
#
# A foreground run is the exception: it has booted the job out, so
# kickstart fails there too, and registering would put a second daemon
# beside it -- both tapping the same applications, the swaps
# cancelling out. run refuses a second copy for the same reason. kickstart restarts a job that is
# already loaded and fails when there is none, which is every machine
# that has not registered yet -- so fall back to registering. That
# difference between the first time and every time after is not
# something anyone should have to remember.
.PHONY: reload
reload: install ## [daily] Build, install and restart the agent under launchd
	@if $(LAUNCHCTL) kickstart -k gui/$(shell id -u)/$(AGENT_LABEL) 2>/dev/null; then \
		echo "Restarted $(AGENT_LABEL)."; \
	elif $(PGREP) -x $(APP_NAME) >/dev/null 2>&1; then \
		echo "$(APP_NAME) is running outside launchd -- a make run, most likely."; \
		echo "Registering now would put a second daemon alongside it, and two"; \
		echo "taps on the same application both fire, so the swaps cancel out."; \
		echo "Stop that one first."; \
		exit 1; \
	else \
		echo "$(AGENT_LABEL) was not loaded; registering it."; \
		"$(INSTALLED_BIN)" register; \
	fi
	$(call report_whether_running)

# Stop the agent and wait for the daemon to go.
#
# Boot the job out rather than signal it: a signal reaches a running
# process only, and the job has none while it sits between KeepAlive
# retries. Booting out leaves the SMAppService registration intact.
#
# bootout returns before the process has gone, so wait up to five
# seconds. $(1) says why that matters to the caller.
define stop_agent
	@echo "Stopping $(AGENT_LABEL); 'make reload' starts it again."
	@$(LAUNCHCTL) bootout gui/$(shell id -u)/$(AGENT_LABEL) 2>/dev/null || true
	@n=0; while $(PGREP) -x $(APP_NAME) >/dev/null 2>&1; do \
		n=$$((n+1)); \
		if [ $$n -gt 50 ]; then \
			echo "$(APP_NAME) is still running; $(1)"; \
			exit 1; \
		fi; \
		sleep 0.1; \
	done
endef

# Stop the agent and leave it stopped. The registration survives, so
# `make reload` starts it again, as does logging in again.
.PHONY: stop
stop: ## [daily] Stop the agent; 'make reload' starts it again
	$(call stop_agent,it was not started by the agent)

# Run the installed binary in the foreground with stdio attached,
# after stopping the agent-managed copy. Two event taps for the same
# app both fire and swap the modifiers twice, cancelling out, so the
# agent has to be out of the way first.
#
# The agent is restored when the foreground copy exits normally; an
# interrupt reaches make as well, so that is then left to you.
.PHONY: run
run: install ## [daily] Run in the foreground instead of under launchd
	$(call stop_agent,refusing to start a second copy)
	@st=0; "$(INSTALLED_BIN)" run || st=$$?; \
	echo "Restoring the agent..."; \
	"$(INSTALLED_BIN)" register || echo "register failed; the agent is stopped. make reload"; \
	exit $$st

# Uninstall: unregister the login item first (while the bundle still
# exists, so SMAppService can resolve it), then remove the bundle.
#
# Boot the job out as well as unregistering it. Unregistering is
# normally enough, but a job that launchd has refused to spawn can
# survive it, and removing the bundle from under a job that is still
# loaded is what leaves the recorded launch requirement in a state
# nothing can satisfy. Booting out is a no-op when the job is gone.
#
# Match the daemon by process name. The agent plist names the program
# through BundleProgram and passes a bare argv[0], so an agent-started
# daemon's command line is "cmd-key-happy --headless" and carries no
# path to match against. migrate-legacy is the other way round: the
# hand-installed plist held the full path, and matching on it is what
# stops us killing the bundled daemon as well.
.PHONY: uninstall
uninstall: ## [install] Unregister and remove the bundle
	@echo "Stopping any running $(APP_NAME) instances..."
	@$(LAUNCHCTL) bootout gui/$(shell id -u)/$(AGENT_LABEL) 2>/dev/null || true
	@$(PKILL) -x "$(APP_NAME)" 2>/dev/null || true
	@set -e; \
	if [ ! -d "$(INSTALLED_BUNDLE)" ]; then \
		echo "$(BUNDLE_NAME) not found in $(INSTALL_DIR)"; \
		exit 0; \
	fi; \
	echo "Unregistering $(AGENT_LABEL)..."; \
	"$(INSTALLED_BIN)" unregister || true; \
	echo "Removing $(BUNDLE_NAME) from $(INSTALL_DIR)..."; \
	$(SUDO) $(RM) -r "$(INSTALLED_BUNDLE)"; \
	echo "Uninstalled $(BUNDLE_NAME)"

# Paths used by the pre-bundle install layout: a bare binary in
# ~/.local/bin supervised by a hand-installed LaunchAgent plist under
# its own label. Nothing shares a name with the bundled install, so
# this only has to boot the job out and delete the files.
LEGACY_LABEL   = com.frobware.cmd-key-happy
LEGACY_PLIST   = $(HOME)/Library/LaunchAgents/$(LEGACY_LABEL).plist
LEGACY_BIN     = $(HOME)/.local/bin/$(APP_NAME)
LEGACY_RESTART = $(HOME)/.local/bin/$(APP_NAME)-restart

.PHONY: migrate-legacy
migrate-legacy: ## [plumbing] Remove the pre-bundle ~/.local/bin install and its agent
	@if [ -f "$(LEGACY_PLIST)" ]; then \
		echo "Booting out legacy agent..."; \
		$(LAUNCHCTL) bootout gui/$(shell id -u)/$(LEGACY_LABEL) 2>/dev/null || true; \
		echo "Removing $(LEGACY_PLIST)"; \
		$(RM) "$(LEGACY_PLIST)"; \
	else \
		echo "No legacy agent plist at $(LEGACY_PLIST)"; \
	fi
	@for f in "$(LEGACY_BIN)" "$(LEGACY_RESTART)"; do \
		if [ -e "$$f" ]; then \
			echo "Removing $$f"; \
			$(RM) "$$f"; \
		fi; \
	done
	@$(PKILL) -f "$(LEGACY_BIN)" 2>/dev/null || true
	@echo "Legacy install cleared. Now: make install && make register"

# Diagnostic snapshot of every place cmd-key-happy might exist: the
# installed bundle and its signature, the build-tree bundle, the
# SMAppService registration, what launchd holds, and whether the
# daemon is running. Reach for this when the answer to "is it actually
# running the binary I just built?" is not obvious.
.PHONY: state
state: ## [check] Check every link in the chain, then print the detail
	@say() { printf "  %-4s %-13s %s\n" "$$1" "$$2" "$$3"; }; \
	NEXT=""; \
	if [ -d "$(INSTALLED_BUNDLE)" ]; then \
		say ok installed "$(INSTALLED_BUNDLE)"; \
	else \
		say FAIL installed "nothing at $(INSTALL_DIR)"; \
		NEXT="make reload"; \
	fi; \
	if [ -z "$$NEXT" ]; then \
		AUTH=$$($(CODESIGN) -dvv "$(INSTALLED_BUNDLE)" 2>&1 | $(SED) -nE 's/^Authority=//p' | head -1); \
		if ! $(CODESIGN) -dv "$(INSTALLED_BUNDLE)" >/dev/null 2>&1; then \
			say FAIL signed "not signed at all -- macOS will not keep a grant for it"; \
			NEXT="make reload, with CODESIGN_IDENTITY set in local.mk"; \
		elif $(CODESIGN) -dv "$(INSTALLED_BUNDLE)" 2>&1 | grep -q "Signature=adhoc"; then \
			say warn signed "ad-hoc: every rebuild costs you the Accessibility grant"; \
		elif [ -z "$$AUTH" ]; then \
			say warn signed "signed, but no authority reported"; \
		else \
			say ok signed "$$AUTH"; \
		fi; \
	else say -- signed "(not checked)"; fi; \
	STATE=""; \
	if [ -z "$$NEXT" ]; then \
		STATE=$$($(LAUNCHCTL) print gui/$(shell id -u)/$(AGENT_LABEL) 2>/dev/null | $(SED) -nE 's/^	state = //p'); \
		if [ -n "$$STATE" ]; then \
			say ok registered "the agent is loaded"; \
		else \
			say FAIL registered "no agent loaded"; \
			NEXT="make reload"; \
		fi; \
	else say -- registered "(not checked)"; fi; \
	if [ -z "$$NEXT" ]; then \
		if [ "$$STATE" = "running" ]; then \
			sleep 0.5; \
			STATE=$$($(LAUNCHCTL) print gui/$(shell id -u)/$(AGENT_LABEL) 2>/dev/null | $(SED) -nE 's/^	state = //p'); \
		fi; \
		if [ "$$STATE" = "running" ]; then \
			say ok running "pid $$($(PGREP) -x $(APP_NAME) | head -1)"; \
			say ok permission "Accessibility granted, or it could not be running"; \
		else \
			say FAIL running "state = $$STATE"; \
			say FAIL permission "almost certainly not granted"; \
			NEXT="switch on $(BUNDLE_NAME) under Privacy & Security > Accessibility (it lists itself, unchecked)"; \
		fi; \
	else say -- running "(not checked)"; say -- permission "(not checked)"; fi; \
	if [ "$$STATE" = "running" ]; then \
		PID=$$($(PGREP) -x $(APP_NAME) | head -1); \
		AGE=$$(ps -p $$PID -o etime= | $(AWK) -F'[-:]' '{ \
			if (NF == 4) print (($$1*24+$$2)*60+$$3)*60+$$4; \
			else if (NF == 3) print (($$1*60)+$$2)*60+$$3; \
			else print ($$1*60)+$$2 }'); \
		TRACE=$$($(LOG) show --predicate "subsystem == \"$(LOG_SUBSYSTEM)\" AND processIdentifier == $$PID AND eventMessage CONTAINS \"event tracing\"" \
			--last $$((AGE + 5))s --style compact 2>/dev/null | tail -1); \
		case "$$TRACE" in \
			*"tracing enabled") say warn tracing "on since $$(echo "$$TRACE" | $(AWK) '{print $$2}') -- make trace turns it off";; \
			*) say ok tracing "off";; \
		esac; \
	fi; \
	CFG="$(HOME)/Library/Application Support/$(BUNDLE_ID)/config"; \
	if [ ! -f "$$CFG" ]; then \
		say FAIL config "none at $$CFG"; \
		[ -n "$$NEXT" ] || NEXT="make reload"; \
	else \
		N=$$($(SED) -E 's/^[[:space:]]+//; s/[[:space:]]+$$//' "$$CFG" | grep -cE '^[^#]' || true); \
		if [ "$$N" -gt 0 ]; then \
			say ok config "$$N application(s) listed"; \
		else \
			say warn config "no applications listed -- nothing is being swapped"; \
			[ -n "$$NEXT" ] || NEXT="list your applications in $$CFG"; \
		fi; \
	fi; \
	echo; \
	if [ -n "$$NEXT" ]; then echo "  Next: $$NEXT"; else echo "  Nothing to do."; fi
	@echo
	@echo "== Installed bundle =="
	@if [ -d "$(INSTALLED_BUNDLE)" ]; then \
		$(LS) -ld "$(INSTALLED_BUNDLE)"; \
		echo "  signature:"; \
		$(CODESIGN) -dv "$(INSTALLED_BUNDLE)" 2>&1 | $(SED) 's/^/    /'; \
	else \
		echo "  (not installed at $(INSTALLED_BUNDLE))"; \
	fi
	@echo
	@echo "== Build-tree bundle =="
	@if [ -d "$(BUNDLE_DIR)" ]; then \
		$(LS) -ld "$(BUNDLE_DIR)"; \
		printf "  spotlight excluded: "; \
		[ -f "$(BUILD_DIR)/.metadata_never_index" ] && echo yes || echo NO; \
	else \
		echo "  (none)"; \
	fi
	@echo
	@echo "== Build metadata (installed) =="
	@if [ -x "$(INSTALLED_BIN)" ]; then \
		"$(INSTALLED_BIN)" version | $(SED) 's/^/  /'; \
	else \
		echo "  (not installed)"; \
	fi
	@echo
	@echo "== Login item =="
	@if [ -x "$(INSTALLED_BIN)" ]; then \
		"$(INSTALLED_BIN)" status | $(SED) 's/^/  /'; \
	else \
		echo "  (not installed)"; \
	fi
	@echo
	@echo "== launchd job =="
	@OUT=$$($(LAUNCHCTL) print gui/$(shell id -u)/$(AGENT_LABEL) 2>/dev/null \
		| $(SED) -nE 's/^	(path|state|pid|program|last exit code) = /  \1 = /p'); \
	if [ -n "$$OUT" ]; then echo "$$OUT"; else echo "  (not loaded)"; fi
	@echo
	@echo "== Running processes =="
	@PS=$$($(PGREP) -lx "$(APP_NAME)" || true); \
	if [ -n "$$PS" ]; then echo "$$PS" | $(SED) 's/^/  /'; else echo "  (none)"; fi
	@echo
	@echo "== Legacy install (pre-bundle) =="
	@FOUND=; \
	for f in "$(LEGACY_PLIST)" "$(LEGACY_BIN)" "$(LEGACY_RESTART)"; do \
		if [ -e "$$f" ]; then echo "  $$f"; FOUND=1; fi; \
	done; \
	if [ -z "$$FOUND" ]; then echo "  (none -- clean)"; \
	else echo "  clear it with: make migrate-legacy"; fi
	@echo
	@echo "== Config =="
	@CFG="$(HOME)/Library/Application Support/$(BUNDLE_ID)/config"; \
	if [ -f "$$CFG" ]; then \
		echo "  $$CFG"; \
		$(SED) 's/^/    /' "$$CFG"; \
	else \
		echo "  (no config at $$CFG)"; \
	fi

# Compact style, minus three things the query has already established:
# the subsystem, which is what it selected on; the process name, since
# one program writes to that subsystem; and the thread id, which never
# changes, because all of this happens on the main queue. What is left
# is the time, the level and the pid -- and the pid earns its place,
# because watching it change is how you notice the daemon restarted
# under you. Twenty columns, which is the difference between a trace
# line fitting and wrapping mid-value. sed -l keeps the output line buffered, without which
# following the log arrives in blocks rather than live.
LOG_TIDY = | $(SED) -l -e 's/\[$(LOG_SUBSYSTEM):default\] //' \
                       -e 's/$(APP_NAME)\[\([0-9][0-9]*\):[0-9a-f]*\]/[\1]/'

# Has the daemon been given the Accessibility permission?
#
# Not by asking it directly. AXIsProcessTrusted answers for the calling
# process, and TCC judges a process started from your terminal under
# the terminal's permissions -- so the installed binary, run by hand
# from a terminal that has Accessibility, reports yes while the agent
# cannot start for want of it.
#
# The copy launchd starts is responsible for itself, and it exits
# non-zero without the permission. So whether that copy is alive is the
# answer, and launchctl knows it without any guessing on our part.
.PHONY: check-accessibility
check-accessibility: ## [check] Say whether the agent has the Accessibility permission
	@STATE=$$($(LAUNCHCTL) print gui/$(shell id -u)/$(AGENT_LABEL) 2>/dev/null \
		| $(SED) -nE 's/^	state = //p'); \
	if [ -z "$$STATE" ]; then \
		echo "unknown: no agent is loaded, so there is nothing to ask."; \
		echo "A registration survives make stop, so this means stopped or"; \
		echo "never registered. Either way: make reload"; \
	elif [ "$$STATE" = "running" ]; then \
		echo "granted: the agent is running, which it cannot do without."; \
	else \
		echo "unknown: the agent is registered but not running (state = $$STATE)."; \
		echo "The permission is the usual cause, and the only one this can"; \
		echo "rule in by the agent running. make show-errors says what it"; \
		echo "actually complained about."; \
		echo ""; \
		echo "  Switch on $(BUNDLE_NAME) under Privacy & Security > Accessibility."; \
		echo "  If it is not listed, add it with + from $(INSTALL_DIR)."; \
		echo ""; \
		echo "Switch it on and launchd starts it within a few seconds."; \
		echo "make show-errors says what it actually complained about."; \
	fi

# Ask the running daemon to start or stop tracing. It has no UI and no
# socket, so a signal is the only way to ask; the trace then goes out
# at notice level, which the unified log keeps, so stream-logs shows it
# live and show-logs still has it afterwards. Nothing needs enabling
# and none of it needs root.
.PHONY: trace
trace: ## [daily] Toggle the per-event trace on the running daemon
	@$(PKILL) -USR1 -x $(APP_NAME) && echo "Signalled $(APP_NAME); the log says which way it went." \
		|| echo "$(APP_NAME) is not running"

# Recent output, then follow. log show cannot follow and log stream
# cannot look back, so the two run in turn: enough context to see how
# the daemon got here -- which build, what it tapped -- and then
# whatever happens next. A line or two may appear twice where the two
# meet.
.PHONY: stream-logs
stream-logs: ## [daily] Recent log output, then follow it live
	$(LOG) show --predicate 'subsystem == "$(LOG_SUBSYSTEM)"' --last 5m --debug --info --style compact $(LOG_TIDY)
	$(LOG) stream --predicate 'subsystem == "$(LOG_SUBSYSTEM)"' --debug --info --style compact $(LOG_TIDY)

# The last hour, after the fact. The trace is in here too if tracing
# was on when the keys were pressed.
.PHONY: show-logs
show-logs: ## [check] Show the last hour of log output
	$(LOG) show --predicate 'subsystem == "$(LOG_SUBSYSTEM)"' --last 1h --debug --info --style compact $(LOG_TIDY)

# Fault as well as error: CKHLog.critical maps to logger.fault, which
# is where a daemon that died on startup reports why. Selecting only
# error would hide exactly what this target exists to show.
.PHONY: show-errors
show-errors: ## [check] Show the last hour of errors and faults
	$(LOG) show --predicate 'subsystem == "$(LOG_SUBSYSTEM)" AND (messageType == error OR messageType == fault)' --last 1h --style compact $(LOG_TIDY)

# Lint both plists. Cheap, and a malformed LaunchAgent plist otherwise
# fails late and opaquely inside SMAppService.
.PHONY: lint-plists
lint-plists: ## [plumbing] plutil -lint both plists
	$(PLUTIL) -lint Info.plist $(AGENT_PLIST)

.PHONY: clean
clean: ## [plumbing] Clean build artifacts and bundle
	$(SWIFT) package clean
	$(RM) -r $(BUILD_DIR)
	@echo "Cleaned build artifacts and bundle"

.PHONY: help
help: ## [plumbing] Show this help message
	@echo "Available targets:"
	@$(AWK) 'BEGIN { \
		FS = ":.*## "; \
		n = split("daily install check plumbing", order, " "); \
		title["daily"] = "Day to day"; \
		title["install"] = "Installing"; \
		title["check"] = "Diagnosis"; \
		title["plumbing"] = "Plumbing"; \
	} \
	/^[a-zA-Z0-9_-]+:.*## \[/ { \
		tag = $$2; sub(/^\[/, "", tag); sub(/\].*/, "", tag); \
		text = $$2; sub(/^\[[a-z-]+\] /, "", text); \
		lines[tag] = lines[tag] sprintf("  %-19s - %s\n", $$1, text); \
	} \
	END { \
		for (i = 1; i <= n; i++) \
			if (lines[order[i]] != "") \
				printf "\n%s\n%s", title[order[i]], lines[order[i]]; \
	}' $(MAKEFILE_LIST)
