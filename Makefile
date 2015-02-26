# Copyright (c) 2009, 2010, 2013 <andrew iain mcdermott via gmail>
#
# Source can be cloned from:
#
# 	git://github.com/andymcd/cmd-key-happy.git
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
INSTALL_ROOT = /usr/local
LUA_HOME     = lua-5.2.1
LIB_LUA      = $(LUA_HOME)/src/liblua.a

DEBUG = -O3

CFLAGS = -I$(LUA_HOME)/src \
	-MMD -Wpointer-arith \
	-Werror \
	-Wall \
	-Wextra \
	-W \
	-Wunused \
	-Wno-unused-parameter \
	-Wno-unused-function \
	-Wuninitialized

LAUNCHD_AGENTS_DIR = $(HOME)/Library/LaunchAgents
LAUNCHD_LABEL = com.frobware.cmd-key-happy
PLIST_FILE = $(LAUNCHD_AGENTS_DIR)/$(LAUNCHD_LABEL).plist

cmd-key-happy : cmd-key-happy.o lua-5.2.1.o
	$(CC) -g -o $@ cmd-key-happy.o lua-5.2.1.o -framework Foundation -framework AppKit -framework Carbon

$(LUA_HOME)/src/liblua.a:
	@$(MAKE) -C $(LUA_HOME) macosx

cmd-key-happy.o : cmd-key-happy.m
	$(CC) $(CFLAGS) -std=c99 $(DEBUG) -c -o $@ $<

lua-5.2.1.o : lua-5.2.1.c
	$(CC) -I$(LUA_HOME)/src $(DEBUG) -c -o $@ $<

%.o : %.m
	$(CC) $(CFLAGS) -c -o $@ $<

.PHONY: install install-rcfile install-plist
.PHONY: start stop clean

install: cmd-key-happy
	$(INSTALL) -d $(INSTALL_ROOT)/bin
	$(INSTALL) -m 555 cmd-key-happy $(INSTALL_ROOT)/bin
	$(INSTALL) -m 555 cmd-key-happy-restart.sh $(INSTALL_ROOT)/bin/cmd-key-happy-restart

install-rcfile:
	cp example-rcfile.lua ~/.cmd-key-happy.lua

install-plist:
	@if [ ! -f ~/.cmd-key-happy.lua ]; then \
		echo "no rcfile; run: make install-rcfile"; \
		exit 1; \
	fi
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

local-lua-install:
	$(MAKE) -C $(LUA_HOME) macosx local

*.o : Makefile

clean: 
	$(RM) cmd-key-happy *.d *.o
	$(RM) -r cmd-key-happy.dSYM

-include *.d

uninstall:
	-$(RM) $(INSTALL_ROOT)/bin/cmd-key-happy
	-$(RM) $(INSTALL_ROOT)/bin/cmd-key-happy-restart
	-launchctl stop $(LAUNCHD_LABEL)
	-launchctl unload $(PLIST_FILE)
	-$(RM) $(PLIST_FILE)
	-pkill cmd-key-happy

TCC_DB = "/Library/Application Support/com.apple.TCC/TCC.db"

install-security-exception-for-cmd-key-happy:
	sudo sqlite3 $(TCC_DB) 'insert or ignore into access values("kTCCServiceAccessibility", "$(INSTALL_ROOT)/bin/cmd-key-happy", 1, 1, 0, null)'
	sudo sqlite3 $(TCC_DB) 'select * from access'

list-tcc-access:
	sudo sqlite3 $(TCC_DB) 'select * from access'

uninstall-security-exception-for-cmd-key-happy:
	sudo sqlite3 $(TCC_DB) 'delete from access where client like "%cmd-key-happy%"'
