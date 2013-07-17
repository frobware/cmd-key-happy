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

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>

#include <string>
#include <algorithm>
#include "EventTap.hpp"

using namespace frobware;

static std::string string_reverse(const std::string& src)
{
  return std::string(src.rbegin(), src.rend());
}

CGEventRef EventTap::handleEvent(CGEventTapProxy proxy,
				 CGEventType type,
				 CGEventRef event,
				 void *arg)
{
  frobware::EventTap *tap = static_cast<frobware::EventTap *>(arg);

  switch (type) {
    case kCGEventTapDisabledByTimeout:
      tap->enable();
      return event;
    case kCGEventTapDisabledByUserInput:
      tap->enable();
      return event;
  }

  const CGEventFlags flags = CGEventGetFlags(event);
  const KeyEvent keyEvent(event);

  // Return unless the event is cmd/alt.

  if (!(keyEvent.isCmdPressed() || keyEvent.isAltPressed())) {
    return event;
  }

  // If both cmd and alt are down then don't swap.

  if (keyEvent.isCmdPressed() && keyEvent.isAltPressed()) {
    return event;
  }

  if (tap->_lastKeyEvent == keyEvent) {
    if (!tap->_keySequenceExcluded) {
      KeyEvent::SwapCmdAndAlt(event, flags);
    }
    return event;
  }

  if (!tap->_excludeKeySet.empty()) {
    const KeyEvent::ID kid = keyEvent.keyCodeWithModifiers();
    const auto iter = tap->_keyCodeMap.find(kid);

    if (iter == tap->_keyCodeMap.end()) {
      tap->_lastKeyStrSeq = std::make_shared<std::string>(string_reverse(KeyEvent::KeyStringSequence(event)));
      tap->_keyCodeMap[kid] = tap->_lastKeyStrSeq;
    } else {
      tap->_lastKeyStrSeq = (*iter).second;
    }

    tap->_keySequenceExcluded = std::binary_search(tap->_excludeKeySet.begin(),
                                                   tap->_excludeKeySet.end(),
                                                   *tap->_lastKeyStrSeq);
    tap->_lastKeyEvent = keyEvent;

    if (tap->_keySequenceExcluded)
      return event;
  }

  return KeyEvent::SwapCmdAndAlt(event, flags);
}

EventTap::EventTap(ProcessSerialNumber psn,
		   const CmdKeyHappy::ExcludeKeySet& excludeKeySet)
    throw(EventTapCreationException)
    : _psn(psn),
      _tapRef(nullptr),
      _lastKeyStrSeq(nullptr),
      _keySequenceExcluded(false),
      _lastKeyEvent(0, 0)
{
  // We reverse the key sequence string because we want the comparison
  // to fail more quickly when comparing in the event handler.  If we
  // don't reverse then we have to trawl through the common parts
  // (i.e., "shift-cmd-", etc) and that will be slower.
  
  std::transform(excludeKeySet.begin(),
                 excludeKeySet.end(),
                 std::back_inserter(_excludeKeySet),
                 string_reverse);

  std::sort(_excludeKeySet.begin(), _excludeKeySet.end());

  _tapRef = ::CGEventTapCreateForPSN(&_psn,
                                     kCGHeadInsertEventTap,
                                     kCGEventTapOptionDefault,
                                     CGEventMaskBit(kCGEventKeyDown),
                                     handleEvent, this);

  if (_tapRef == nullptr) {
    throw EventTapCreationException(strerror(errno));
  }

  ScopedCF<CFRunLoopSourceRef> source(::CFMachPortCreateRunLoopSource(NULL, _tapRef, 0));
  ::CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
}

EventTap::~EventTap()
{
  if (_tapRef) {
    ScopedCF<CFRunLoopSourceRef> source(::CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _tapRef, 0));
    NSRunLoop *loop = [NSRunLoop mainRunLoop];
    ::CFRunLoopRemoveSource([loop getCFRunLoop], source, kCFRunLoopDefaultMode);
    ::CFMachPortInvalidate(_tapRef);
    ::CFRelease(_tapRef);
  }
}

void EventTap::enable()
{
  ::CGEventTapEnable(_tapRef, true);
}
