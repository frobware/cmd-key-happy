DEBUG = -O3

CXXFLAGS = $(DEBUG) -MMD -I$(LUA_HOME) -std=c++11 -stdlib=libc++
CFLAGS = $(DEBUG) -MMD -I$(LUA_HOME)

#-std=c++11 -stdlib=libc++
# -Wno-c++11-extensions -Wno-disabled-macro-expansion $(DEBUG)

ROOT = $(shell pwd)

.PHONY: test build clean

SRCS = $(wildcard *.mm) $(wildcard test/*.mm)
OBJS = $(patsubst %.mm,%.o,$(SRCS))

LUA_HOME     = ../lua-5.2.1
LIB_LUA      = $(LUA_HOME)/src/liblua.a

cmd-key-happy: $(OBJS) lua-5.2.1.o 
	$(CXX) $(DEBUG) -o $@ $(filter-out test/%.o,$(OBJS)) lua-5.2.1.o -framework AppKit -framework Carbon

test/%.o : test/%.mm
	$(COMPILE.cpp) -I. -o $@ $<

lua-5.2.1.o : ../lua-5.2.1.c
	$(COMPILE.c) -I$(LUA_HOME)/src $(DEBUG) -c -o $@ $<

%.o : %.mm
	$(COMPILE.cpp) -Wno-deprecated-declarations -o $@ $<

test: build
	python test.py

build:
	python setup.py -q build_ext --inplace

clean:
#	python setup.py clean
	$(RM) -rf build
	$(RM) -rf *.d test/*.d $(OBJS)

*.o : Makefile

-include *.d
-include test/*.d

TAGS:
	etags *.hpp *.mm
