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
build:
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
bundle: build $(ICNS)
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
install: bundle
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
.PHONY: register
register:
	"$(INSTALLED_BIN)" register

.PHONY: unregister
unregister:
	"$(INSTALLED_BIN)" unregister

.PHONY: status
status:
	"$(INSTALLED_BIN)" status

.PHONY: version
version:
	"$(INSTALLED_BIN)" version

# Check the configuration file is present and readable without
# starting the daemon. Those are the conditions the daemon exits on,
# so catching them here beats a job that fails on start and is
# restarted in a loop by KeepAlive. There is no grammar to check:
# every non-empty line is an app name, and a name matching no running
# application is simply never tapped.
.PHONY: parse-config
parse-config:
	"$(INSTALLED_BIN)" --parse-config

# Inner-loop iteration: rebuild, reinstall, and bounce the agent so
# the new binary is picked up. kickstart -k kills the running job and
# restarts it in one step; the job must already be registered.
.PHONY: reload
reload: install
	@echo "Restarting $(AGENT_LABEL)..."
	$(LAUNCHCTL) kickstart -k gui/$(shell id -u)/$(AGENT_LABEL)
	@echo "Restarted. Follow along with: make stream-logs"

# Stop the agent and wait for the daemon to actually go.
#
# Boot the job out rather than signal it. A signal reaches a running
# process only, and the job has no process while it sits between
# KeepAlive retries after a failed start -- exactly the state you want
# it stopped in. The signal would be a no-op and launchd's scheduled
# retry would start it again underneath you.
#
# Booting out leaves the SMAppService registration intact, so register
# brings it back without a full re-registration.
#
# bootout returns before the process has gone, so wait for it: five
# seconds, then give up and say so. $(1) is what to say about why that
# matters to the caller.
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
stop:
	$(call stop_agent,it was not started by the agent)

# Run the installed binary in the foreground with stdio attached,
# after stopping the agent-managed copy. Two event taps for the same
# app both fire and swap the modifiers twice, cancelling out, so the
# agent has to be out of the way first.
#
# The agent is restored when the foreground copy exits normally; an
# interrupt reaches make as well, so that is then left to you.
.PHONY: run
run: install
	$(call stop_agent,refusing to start a second copy)
	@st=0; "$(INSTALLED_BIN)" || st=$$?; \
	echo "Restoring the agent..."; \
	"$(INSTALLED_BIN)" register || true; \
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
uninstall:
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
migrate-legacy:
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
state:
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

# Live log streaming for the daemon's os_log subsystem. Note that
# debug-level messages (the per-keystroke swap trace) are not
# persisted unless you enable them for the subsystem:
#   sudo log config --mode "level:debug" --subsystem $(LOG_SUBSYSTEM)
.PHONY: stream-logs
stream-logs:
	$(LOG) stream --predicate 'subsystem == "$(LOG_SUBSYSTEM)"' --debug --info

.PHONY: show-logs
show-logs:
	$(LOG) show --predicate 'subsystem == "$(LOG_SUBSYSTEM)"' --last 1h --debug --info

# Fault as well as error: CKHLog.critical maps to logger.fault, which
# is where a daemon that died on startup reports why. Selecting only
# error would hide exactly what this target exists to show.
.PHONY: show-errors
show-errors:
	$(LOG) show --predicate 'subsystem == "$(LOG_SUBSYSTEM)" AND (messageType == error OR messageType == fault)' --last 1h

# Lint both plists. Cheap, and a malformed LaunchAgent plist otherwise
# fails late and opaquely inside SMAppService.
.PHONY: lint-plists
lint-plists:
	$(PLUTIL) -lint Info.plist $(AGENT_PLIST)

.PHONY: clean
clean:
	$(SWIFT) package clean
	$(RM) -r $(BUILD_DIR)
	@echo "Cleaned build artifacts and bundle"

.PHONY: help
help:
	@echo "Available targets:"
	@echo "  build          - Build the Swift package"
	@echo "  bundle         - Build, assemble, inject metadata, and sign $(BUNDLE_NAME) (default)"
	@echo "  install        - Install bundle to \$$INSTALL_DIR (default ~/Applications)"
	@echo "  register       - Register the bundled LaunchAgent via SMAppService"
	@echo "  unregister     - Unregister the LaunchAgent"
	@echo "  status         - Print SMAppService registration status"
	@echo "  version        - Print build metadata for the installed bundle"
	@echo "  parse-config   - Validate the config file without starting the daemon"
	@echo "  reload         - install + kickstart the agent onto the new binary"
	@echo "  stop           - Stop the agent; 'make register' starts it again"
	@echo "  run            - install + stop the agent + run in the foreground"
	@echo "  uninstall      - Unregister and remove the bundle"
	@echo "  migrate-legacy - Remove the pre-bundle ~/.local/bin install and its agent"
	@echo "  state          - Print where cmd-key-happy is installed, registered, and running"
	@echo "  stream-logs    - Tail os_log output for $(LOG_SUBSYSTEM)"
	@echo "  show-logs      - Show last 1h of os_log output"
	@echo "  show-errors    - Show last 1h of error-level os_log output"
	@echo "  lint-plists    - plutil -lint both plists"
	@echo "  clean          - Clean build artifacts and bundle"
	@echo "  help           - Show this help message"
