# -*- cmake -*-

# I tend to use the CMake build for creating an Xcode project and then
# using the analysis features.  To do this you can do the
# following:
#
#   mkdir xcode-build
#   cmake -G Xcode ..
#   open CMD_KEY_HAPPY.xcodeproj
#
# and then build and analyze from the Project menu.

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

add_definitions("-DLUA_USE_MACOSX")
add_definitions("-DLUA_COMPAT_ALL")
include_directories(${CMD_KEY_HAPPY_SOURCE_DIR}/lua-5.2.1/src)

set(SRCS
  cmd-key-happy.m
  lua-5.2.1/src/lapi.c
  lua-5.2.1/src/lauxlib.c
  lua-5.2.1/src/lbaselib.c
  lua-5.2.1/src/lbitlib.c
  lua-5.2.1/src/lcode.c
  lua-5.2.1/src/lcorolib.c
  lua-5.2.1/src/lctype.c
  lua-5.2.1/src/ldblib.c
  lua-5.2.1/src/ldebug.c
  lua-5.2.1/src/ldo.c
  lua-5.2.1/src/ldump.c
  lua-5.2.1/src/lfunc.c
  lua-5.2.1/src/lgc.c
  lua-5.2.1/src/linit.c
  lua-5.2.1/src/liolib.c
  lua-5.2.1/src/llex.c
  lua-5.2.1/src/lmathlib.c
  lua-5.2.1/src/lmem.c
  lua-5.2.1/src/loadlib.c
  lua-5.2.1/src/lobject.c
  lua-5.2.1/src/lopcodes.c
  lua-5.2.1/src/loslib.c
  lua-5.2.1/src/lparser.c
  lua-5.2.1/src/lstate.c
  lua-5.2.1/src/lstring.c
  lua-5.2.1/src/lstrlib.c
  lua-5.2.1/src/ltable.c
  lua-5.2.1/src/ltablib.c
  lua-5.2.1/src/ltm.c
  lua-5.2.1/src/lundump.c
  lua-5.2.1/src/lvm.c
  lua-5.2.1/src/lzio.c)

set_source_files_properties(cmd-key-happy.m PROPERTIES COMPILE_FLAGS "-std=c99 -Wall -Wunused -Wno-unused-parameter")
set_source_files_properties(${SRCS} PROPERTIES LANGUAGE C)

add_executable(cmd-key-happy ${SRCS})
target_link_libraries(cmd-key-happy "-framework Foundation -framework AppKit -framework Carbon")

message("CMAKE_SYSTEM=${CMAKE_SYSTEM}")
message("CMAKE_GENERATOR=${CMAKE_GENERATOR}")
message("CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}")
