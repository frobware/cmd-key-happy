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

INSTALL      = /usr/bin/install
INSTALL_ROOT = $(HOME)/.local

LAUNCHD_AGENTS_DIR = $(HOME)/Library/LaunchAgents
LAUNCHD_LABEL = com.frobware.cmd-key-happy
PLIST_FILE = $(LAUNCHD_AGENTS_DIR)/$(LAUNCHD_LABEL).plist

# Build mode: debug or release (default: release)
BUILD_MODE ?= release
BUILD_DIR = .build/$(BUILD_MODE)
CMD_KEY_HAPPY_BINARY = $(BUILD_DIR)/cmd-key-happy

cmd-key-happy:
	swift build -c $(BUILD_MODE)

.PHONY: install install-plist
.PHONY: start stop clean

install: cmd-key-happy
	$(INSTALL) -d $(INSTALL_ROOT)/bin
	$(INSTALL) -m 555 $(CMD_KEY_HAPPY_BINARY) $(INSTALL_ROOT)/bin/cmd-key-happy
	$(INSTALL) -m 555 cmd-key-happy-restart.sh $(INSTALL_ROOT)/bin/cmd-key-happy-restart

install-plist:
	mkdir -p $(LAUNCHD_AGENTS_DIR)
	-launchctl stop $(LAUNCHD_LABEL)
	-launchctl unload $(PLIST_FILE)
	$(RM) $(PLIST_FILE)
	sed -e 's~%INSTALL_ROOT~$(INSTALL_ROOT)~' $(LAUNCHD_LABEL).plist > $(PLIST_FILE)
	chmod 644 $(PLIST_FILE)
	launchctl load -S Aqua $(PLIST_FILE)
	launchctl start $(LAUNCHD_LABEL)

stop:
	launchctl stop $(LAUNCHD_LABEL)

start:
	launchctl start $(LAUNCHD_LABEL)

uninstall:
	-pkill cmd-key-happy
	-$(RM) $(INSTALL_ROOT)/bin/cmd-key-happy
	-$(RM) $(INSTALL_ROOT)/bin/cmd-key-happy-restart
	-launchctl stop $(LAUNCHD_LABEL)
	-launchctl unload $(PLIST_FILE)
	-$(RM) $(PLIST_FILE)

TCC_DB = "/Library/Application Support/com.apple.TCC/TCC.db"

install-security-exception-for-cmd-key-happy:
	sudo sqlite3 $(TCC_DB) 'insert or ignore into access values("kTCCServiceAccessibility", "$(INSTALL_ROOT)/bin/cmd-key-happy", 1, 1, 0, null)'
	sudo sqlite3 $(TCC_DB) 'select * from access'

list-tcc-access:
	sudo sqlite3 $(TCC_DB) 'select * from access'

uninstall-security-exception-for-cmd-key-happy:
	sudo sqlite3 $(TCC_DB) 'delete from access where client like "%cmd-key-happy%"'

clean:
	swift package clean
	rm -rf .build
