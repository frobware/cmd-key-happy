# Copyright (c) 2015 <andrew iain mcdermott via gmail>
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

DEBUG = -O3

INSTALL      = /usr/bin/install
INSTALL_ROOT = /usr/local

CXXFLAGS = $(DEBUG) -MMD -std=c++11 -stdlib=libc++
CFLAGS = $(DEBUG) -MMD

LAUNCHD_AGENTS_DIR = $(HOME)/Library/LaunchAgents
LAUNCHD_LABEL = com.frobware.cmd-key-happy
PLIST_FILE = $(LAUNCHD_AGENTS_DIR)/$(LAUNCHD_LABEL).plist

.PHONY: build clean

SRCS = $(wildcard *.mm)
OBJS = $(patsubst %.mm,%.o,$(SRCS))

LUA_HOME     = ../lua-5.2.1
LIB_LUA      = $(LUA_HOME)/src/liblua.a

all: cmd-key-happy lua2rc

cmd-key-happy: $(OBJS)
	$(CXX) $(DEBUG) -o $@ $(OBJS) -framework AppKit -framework Carbon

lua2rc: lua2rc.o lua-5.2.1.o
	$(CC) -o $@ lua2rc.o lua-5.2.1.o -framework AppKit

lua-5.2.1.o: ../lua-5.2.1.c
	$(COMPILE.c) -I$(LUA_HOME)/src $(DEBUG) -o $@ $<

lua2rc.o: lua2rc.m
	$(COMPILE.c) -I$(LUA_HOME)/src $(DEBUG) -o $@ $<

%.o: %.mm
	$(COMPILE.cpp) -Wno-deprecated-declarations -o $@ $<

clean:
	$(RM) -rf build
	$(RM) -rf *.d test/*.d $(OBJS)

*.o: Makefile

-include *.d

TAGS:
	etags *.hpp *.mm *.m

install: cmd-key-happy
	$(INSTALL) -d $(INSTALL_ROOT)/bin
	$(INSTALL) -m 555 cmd-key-happy $(INSTALL_ROOT)/bin
	$(INSTALL) -m 555 cmd-key-happy-restart.sh $(INSTALL_ROOT)/bin/cmd-key-happy-restart

install-rcfile:
	[ -f $$HOME/.cmd-key-happy.rc ] || cp example-rcfile.rc $$HOME/.cmd-key-happy.rc;

install-plist:
	@if [ ! -f ~/.cmd-key-happy.lua ]; then \
		echo "no rcfile; run: make install-rcfile"; \
		exit 1; \
	fi
	mkdir -p $(LAUNCHD_AGENTS_DIR)
	sed -e 's~%INSTALL_ROOT~$(INSTALL_ROOT)~' $(LAUNCHD_LABEL).plist > $(PLIST_FILE)
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

uninstall:
	-$(RM) $(INSTALL_ROOT)/bin/cmd-key-happy
	-$(RM) $(INSTALL_ROOT)/bin/cmd-key-happy-restart
	-launchctl stop $(LAUNCHD_LABEL)
	-launchctl unload $(PLIST_FILE)
	-$(RM) $(PLIST_FILE)
	-pkill cmd-key-happy

TCC_DB = "/Library/Application Support/com.apple.TCC/TCC.db"

tcc-install-security-exception:
	sqlite3 $(TCC_DB) 'insert or ignore into access values("kTCCServiceAccessibility", "$(INSTALL_ROOT)/bin/cmd-key-happy", 0, 0, 1, null)'
	sqlite3 $(TCC_DB) 'select * from access'

tcc-list-access:
	sqlite3 $(TCC_DB) 'select * from access'

tcc-uninstall-security-exception:
	sqlite3 $(TCC_DB) 'delete from access where client like "%cmd-key-happy%"'
	sqlite3 $(TCC_DB) 'delete from access where client like "com.apple.Terminal"'
