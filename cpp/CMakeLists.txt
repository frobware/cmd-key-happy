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

set(SRCS CmdKeyHappy.mm	EventTap.mm KeyEvent.mm	ProcessInfo.mm ProcessList.mm main.mm KeySeq.mm)

set_source_files_properties(${SRCS} PROPERTIES LANGUAGE CXX)

add_definitions(${CMAKE_CXX_FLAGS} "-std=c++11")
add_definitions(${CMAKE_CXX_FLAGS} "-stdlib=libc++")

set(CMAKE_CXX_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -std=c++11 -stdlib=libc++")
set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -std=c++11 -stdlib=libc++ -O4")

add_executable(cmd-key-happy ${SRCS})
target_link_libraries(cmd-key-happy "-framework Foundation -framework AppKit -framework Carbon -lc++")

message("CMAKE_SYSTEM=${CMAKE_SYSTEM}")
message("CMAKE_GENERATOR=${CMAKE_GENERATOR}")
message("CMAKE_BUILD_TYPE=${CMAKE_BUILD_TYPE}")
