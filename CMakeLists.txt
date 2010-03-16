# -*- cmake -*-

# The name of our project is "CMD_KEY_HAPPY". Files in this project
# can refer to the source directory of the project as
# ${CMD_KEY_HAPPY_SOURCE_DIR} and to the root binary directory of the
# project as ${CMD_KEY_HAPPY_BINARY_DIR}.

cmake_minimum_required(VERSION 2.6)
project(CMD_KEY_HAPPY)

set(CMAKE_ALLOW_LOOSE_LOOP_CONSTRUCTS true)

#
# We don't allow in-source builds.
#
if(${CMAKE_SOURCE_DIR} STREQUAL ${CMAKE_BINARY_DIR})
  message(FATAL_ERROR "

CMake generation is not allowed within the source directory!  You
*MUST* remove the CMakeCache.txt file and try again from another
directory,

For example:
   rm CMakeCache.txt
   mkdir xcode-build
   cd xcode-build
   cmake -G \"Xcode\" ..
")
endif()

add_definitions("-DLUA_USE_LINUX")
include_directories(${CMD_KEY_HAPPY_SOURCE_DIR}/lua-5.1.4/src)

set(SRCS
  cmd-key-happy.m
  lua-5.1.4/src/lapi.c
  lua-5.1.4/src/lcode.c
  lua-5.1.4/src/ldebug.c
  lua-5.1.4/src/ldo.c
  lua-5.1.4/src/ldump.c
  lua-5.1.4/src/lfunc.c
  lua-5.1.4/src/lgc.c
  lua-5.1.4/src/llex.c
  lua-5.1.4/src/lmem.c
  lua-5.1.4/src/lobject.c
  lua-5.1.4/src/lopcodes.c
  lua-5.1.4/src/lparser.c
  lua-5.1.4/src/lstate.c
  lua-5.1.4/src/lstring.c
  lua-5.1.4/src/ltable.c
  lua-5.1.4/src/ltm.c
  lua-5.1.4/src/lundump.c
  lua-5.1.4/src/lvm.c
  lua-5.1.4/src/lzio.c
  lua-5.1.4/src/lauxlib.c
  lua-5.1.4/src/lbaselib.c
  lua-5.1.4/src/ldblib.c
  lua-5.1.4/src/liolib.c
  lua-5.1.4/src/lmathlib.c
  lua-5.1.4/src/loslib.c
  lua-5.1.4/src/ltablib.c
  lua-5.1.4/src/lstrlib.c
  lua-5.1.4/src/loadlib.c
  lua-5.1.4/src/linit.c)

set_source_files_properties(cmd-key-happy.m PROPERTIES COMPILE_FLAGS "-std=c99 -Wall -Wunused -Wno-unused-parameter")
set_source_files_properties(${SRCS} PROPERTIES LANGUAGE C)

add_executable(cmd-key-happy ${SRCS})
target_link_libraries(cmd-key-happy "-framework Foundation -framework AppKit -framework Carbon")

message("CMAKE_SYSTEM=${CMAKE_SYSTEM}")
message("CMAKE_GENERATOR=${CMAKE_GENERATOR}")
message("CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}")
