/*
 * Copyright (c) 2013 <andrew.iain.mcdermott@gmail.com>
 *
 * Source can be cloned from:
 *
 * 	git://github.com/aim-stuff/cmd-key-happy.git
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

#import <Foundation/Foundation.h>

#include <vector>
#include <map>
#include <stdexcept>
#include <memory>
#include "CmdKeyHappy.hpp"
#include "ProcessInfo.hpp"
#include "KeyEvent.hpp"
#include "ScopedCF.hpp"

namespace frobware {

class EventTapCreationException : public std::runtime_error {
 public:
  EventTapCreationException(const char *msg) : std::runtime_error(msg) {}
  ~EventTapCreationException() throw() {}
};

class EventTap
{
 public:
  EventTap(ProcessSerialNumber psn,
           const CmdKeyHappy::ExcludeKeySet& excludeKeySet)
      throw(EventTapCreationException);
  ~EventTap();
 private:
  EventTap(const EventTap& other) = delete;
  EventTap& operator=(const EventTap& other) = delete;
  
  static CGEventRef handleEvent(CGEventTapProxy proxy,
                                CGEventType type,
                                CGEventRef event,
                                void *arg);
  void enable();
  typedef std::map<KeyEvent::ID, std::shared_ptr<std::string> > KeyCodeMap;
  ProcessSerialNumber _psn;
  KeyCodeMap _keyCodeMap;
  std::vector<std::string> _excludeKeySet;
  CFMachPortRef _tapRef;
  std::shared_ptr<std::string> _lastKeyStrSeq;
  bool _keySequenceExcluded;
  KeyEvent _lastKeyEvent;
};

} // namespace frobware
