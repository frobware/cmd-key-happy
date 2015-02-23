DEBUG = -O3

CXXFLAGS = $(DEBUG) -MMD -std=c++11 -stdlib=libc++
CFLAGS = $(DEBUG) -MMD

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
