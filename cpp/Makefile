DEBUG = -g
DEBUG += -std=c++11 -stdlib=libc++

CXX = /usr/bin/clang++

CXXFLAGS = $(DEBUG) -MMD

ROOT = $(shell pwd)

.PHONY: test build clean

SRCS = $(wildcard *.mm) $(wildcard test/*.mm)
OBJS = $(patsubst %.mm,%.o,$(SRCS))

cmd-key-happy: $(OBJS)
	$(CXX) $(DEBUG) -o $@ $(filter-out test/%.o,$(OBJS)) -framework AppKit -framework Carbon

test/%.o : test/%.mm
	$(COMPILE.cpp) -I. -o $@ $<

%.o : %.mm
	$(COMPILE.cpp) -o $@ $<

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
