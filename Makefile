# Copyright (c) 2009, 2010 <Andrew Iain McDermott _at_ gmail>
#
# Source can be cloned from:
#
# 	git://github.com/aim-stuff/cmd-key-happy.git
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
LUA_HOME     = lua-5.1.4

CFLAGS       = -I$(LUA_HOME)/src \
               -std=c99 -MMD -Wpointer-arith \
               -Wall -Wextra -W -Werror -Wunused -Wno-unused-parameter -Wno-unused-function -Wuninitialized -O3 -g

LUA_LIB_SRCS =	lapi.c lcode.c ldebug.c ldo.c ldump.c lfunc.c lgc.c llex.c	\
		lmem.c lobject.c lopcodes.c lparser.c lstate.c lstring.c	\
		ltable.c ltm.c lundump.c lvm.c lzio.c				\
		lauxlib.c lbaselib.c ldblib.c liolib.c lmathlib.c loslib.c	\
		ltablib.c lstrlib.c loadlib.c linit.c

LUA_LIB_OBJS = $(LUA_LIB_SRCS:.c=.o)
VPATH        = $(LUA_HOME)/src

LAUNCHD_AGENTS_DIR = $(HOME)/Library/LaunchAgents
LAUNCHD_LABEL = com.frobware.cmd-key-happy
PLIST_FILE = $(LAUNCHD_AGENTS_DIR)/$(LAUNCHD_LABEL).plist

cmd-key-happy : cmd-key-happy.o $(LUA_LIB_OBJS)
	$(CC) -g -o $@ cmd-key-happy.o $(LUA_LIB_OBJS) -framework Foundation -framework AppKit -framework Carbon

cmd-key-happy.o : cmd-key-happy.m
	$(CC) $(CFLAGS) -c -o $@ $<

%.o : %.m
	$(CC) $(CFLAGS) -c -o $@ $<

%.o : $(LUA_HOME)/src/%.c
	$(CC) -MMD -Wall -O2 -DLUA_USE_LINUX -c -o $@ $<

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
	$(MAKE) -C $(LUA_HOME) clean

-include *.d
