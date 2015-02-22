/*
 * Copyright (c) 2013 <andrew.iain.mcdermott@gmail.com>
 *
 * Source can be cloned from:
 *
 * 	git://github.com/andymcd/cmd-key-happy.git
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to
 * deal in the Software without restriction, including without limitation the
 * rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

#pragma once

#import <Carbon/Carbon.h>
#include <map>
#include <set>
#include "ProcessList.hpp"
#include "AppSpec.hpp"

namespace frobware {

class EventTap;

class CmdKeyHappy {
 public:
  static CmdKeyHappy* Instance();
  void run();
  void registerApp(const AppSpec& app);
 private:
  typedef std::map<ProcessSerialNumber, EventTap *> TapMap;
  typedef std::map<std::string, AppSpec> AppMap;

  static OSStatus eventHandler(EventHandlerCallRef callref,
                               EventRef            event,
                               void *              arg);

  CmdKeyHappy() {}
  CmdKeyHappy(const CmdKeyHappy& other) = delete;
  CmdKeyHappy& operator=(const CmdKeyHappy& rhs) = delete;

  bool isAppRegistered(const std::string& appname) const;
  void tapApp(const ProcessInfo& proc);
  void appTerminated(ProcessSerialNumber psn);

  TapMap _tapMap;
  AppMap _appMap;
  static CmdKeyHappy *_instance;
};

} // namespace frobware
