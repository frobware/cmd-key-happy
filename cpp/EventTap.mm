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

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>

#include <string>
#include <algorithm>
#include "EventTap.hpp"
#include "AppSpec.hpp"
#include "KeySeq.hpp"

using namespace frobware;

struct EscapableUnicodeKey {
  EscapableUnicodeKey(unichar x) :_uc(x) {}
  EscapableUnicodeKey(unichar x, const char *str) :_uc(x), _name(str) {}
  unichar _uc;
  const char *_name;
  bool operator==(const EscapableUnicodeKey& other) const {
    return _uc == other._uc;
  }
};

static std::vector<EscapableUnicodeKey> escapableKeySet {
  { 0x0003, "enter" },
  { 0x0008, "backspace" },
  { 0x0009, "tab" },
  { 0x000a, "newline" },
  { 0x000c, "formfeed" },
  { 0x000d, "return" },
  { 0x0019, "tab" },
  { 0x001b, "escape" },
  { 0x0020, "space" },
  { 0x007f, "delete" },
  { 0x2028, "linesep" },
  { 0x2029, "paragrapsep" },
  { 0xf700, "up" },
  { 0xf701, "down" },
  { 0xf702, "left" },
  { 0xf703, "right" },
  { 0xf704, "F1" },
  { 0xf705, "F2" },
  { 0xf706, "F3" },
  { 0xf707, "F4" },
  { 0xf708, "F5" },
  { 0xf709, "F6" },
  { 0xf70a, "F7" },
  { 0xf70b, "F8" },
  { 0xf70c, "F9" },
  { 0xf70d, "F10" },
  { 0xf70e, "F11" },
  { 0xf70f, "F12" },
  { 0xf710, "F13" },
  { 0xf711, "F14" },
  { 0xf712, "F15" },
  { 0xf713, "F16" },
  { 0xf714, "F17" },
  { 0xf715, "F18" },
  { 0xf716, "F19" },
  { 0xf717, "F20" },
  { 0xf718, "F21" },
  { 0xf719, "F22" },
  { 0xf71a, "F23" },
  { 0xf71b, "F24" },
  { 0xf71c, "F25" },
  { 0xf71d, "F26" },
  { 0xf71e, "F27" },
  { 0xf71f, "F28" },
  { 0xf720, "F29" },
  { 0xf721, "F30" },
  { 0xf722, "F31" },
  { 0xf723, "F32" },
  { 0xf724, "F33" },
  { 0xf725, "F34" },
  { 0xf726, "F35" },
  { 0xf727, "insert" },
  { 0xf728, "delete" },
  { 0xf729, "home" },
  { 0xf72a, "begin" },
  { 0xf72b, "end" },
  { 0xf72c, "page up" },
  { 0xf72d, "page down" },
  { 0xf72e, "print" },
  { 0xf72f, "scroll lock" },
  { 0xf730, "pause" },
  { 0xf731, "sysreq" },
  { 0xf732, "break" },
  { 0xf733, "reset" },
  { 0xf734, "stop" },
  { 0xf735, "menu" },
  { 0xf736, "user" },
  { 0xf737, "system" },
  { 0xf738, "print" },
  { 0xf739, "clearline" },
  { 0xf73a, "cleardpy" },
  { 0xf73b, "insertline" },
  { 0xf73c, "deleteline" },
  { 0xf73d, "insertchar" },
  { 0xf73e, "deletechar" },
  { 0xf73f, "prev" },
  { 0xf740, "next" },
  { 0xf741, "select" },
  { 0xf742, "execute" },
  { 0xf743, "undo" },
  { 0xf744, "redo" },
  { 0xf745, "find" },
  { 0xf746, "help" },
  { 0xf747, "modeswitch" },
};

/*
 * Translate the virtual keycode to a character representation.  This
 * function does not handle the modifier keys.  It also translates
 * certain keys to more human readable forms (e.g., "tab", "space",
 * "up").  Because no modifiers are considered a "shift-n" will return
 * "n", not "N".
 */
static std::string translateKeycode(CGKeyCode keyCode, CGEventRef event)
{
  CGEventSourceRef source;

  if ((source = CGEventCreateSourceFromEvent(event)) == NULL)
    return "";

  TISInputSourceRef currentKeyboard = ::TISCopyCurrentKeyboardInputSource();
  CFDataRef uchr = (CFDataRef)::TISGetInputSourceProperty(currentKeyboard, kTISPropertyUnicodeKeyLayoutData);

  if (uchr == nil) {
    CFRelease(source);
    return "";
  }

  const UCKeyboardLayout *keyboardLayout = (const UCKeyboardLayout *)::CFDataGetBytePtr(uchr);
  UInt32 keyboardType = ::CGEventSourceGetKeyboardType(source);

  CFRelease(source);

  assert(currentKeyboard);
  assert(uchr);
  assert(keyboardLayout);

  if (keyboardLayout == NULL) {
    NSLog(@"no keyboard layout");
    return "";
  }

  UInt32 deadKeyState = 0;
  UInt32 modifierKeyState = 0;
  UniCharCount actualStringLength = 0;
  UniChar unicodeString[5];
  OSStatus status = ::UCKeyTranslate(keyboardLayout,
                                     keyCode,
                                     kUCKeyActionDisplay,
                                     modifierKeyState,
                                     keyboardType,
                                     kUCKeyTranslateNoDeadKeysBit,
                                     &deadKeyState,
                                     sizeof unicodeString / sizeof unicodeString[0],
                                     &actualStringLength,
                                     unicodeString);

  if (status != noErr)
    return "";

  if (actualStringLength < 1)
    return "";

  NSEvent *nsevent = [NSEvent eventWithCGEvent:event];
  NSString *input = [nsevent charactersIgnoringModifiers];

  if (input != nil) {
    const auto iter = std::find(escapableKeySet.begin(),
                                escapableKeySet.end(),
                                [input characterAtIndex:0]);

    if (iter != escapableKeySet.end()) {
      return (*iter)._name;
    }
  }
  
  return std::string([[NSString stringWithCharacters:unicodeString length:actualStringLength] UTF8String]);
}

static CGEventRef SwapCmdAndAlt(CGEventRef event, CGEventFlags flags)
{
  if (flags & kCGEventFlagMaskCommand) {
    flags &= ~kCGEventFlagMaskCommand;
    flags |= kCGEventFlagMaskAlternate;
    if (flags & NX_DEVICELCMDKEYMASK) {
      flags &= ~NX_DEVICELCMDKEYMASK;
      flags |= NX_DEVICELALTKEYMASK;
    }
    if (flags & NX_DEVICERCMDKEYMASK) {
      flags &= ~NX_DEVICERCMDKEYMASK;
      flags |= NX_DEVICERALTKEYMASK;
    }
    CGEventSetFlags(event, flags);
  } else if (flags & kCGEventFlagMaskAlternate) {
    flags &= ~kCGEventFlagMaskAlternate;
    flags |= kCGEventFlagMaskCommand;
    if (flags & NX_DEVICELALTKEYMASK) {
      flags &= ~NX_DEVICELALTKEYMASK;
      flags |= NX_DEVICELCMDKEYMASK;
    }
    if (flags & NX_DEVICERALTKEYMASK) {
      flags &= ~NX_DEVICERALTKEYMASK;
      flags |= NX_DEVICERCMDKEYMASK;
    }
    CGEventSetFlags(event, flags);
  }

  return event;
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

  const CGEventFlags flags = ::CGEventGetFlags(event);

  bool altDown = flags & kCGEventFlagMaskAlternate;
  bool cmdDown = flags & kCGEventFlagMaskCommand;
  
  // Return unless the event is cmd/alt.

  if (!(cmdDown || altDown)) {
    return event;
  }

  // If both cmd and alt are down then don't swap.

  if (cmdDown && altDown) {
    return event;
  }

  const CGKeyCode keyCode = ::CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);

  if (keyCode == tap->_lastKeyEvent.keyCode) {
    if (tap->_lastKeyEvent.isExcluded) {
      return event;
    } else {
      return SwapCmdAndAlt(event, flags);
    }
  }
  
  KeySeq keySeq(translateKeycode(keyCode, event), 
		(flags & kCGEventFlagMaskShift) |
		(flags & kCGEventFlagMaskControl) |
		(flags & kCGEventFlagMaskAlternate) |
		(flags & kCGEventFlagMaskCommand));

  tap->_lastKeyEvent.keyCode = keyCode;

  if (tap->_appSpec.isKeySequenceExcluded(keySeq)) {
    tap->_lastKeyEvent.isExcluded = true;
    return event;
  } else {
    tap->_lastKeyEvent.isExcluded = false;
    return SwapCmdAndAlt(event, flags);
  }
}

EventTap::EventTap(ProcessSerialNumber psn,
		   const AppSpec& appSpec)
    throw(EventTapCreationException)
    : _psn(psn),
      _tapRef(nullptr),
      _appSpec(appSpec)
{
  _tapRef = ::CGEventTapCreateForPSN(&_psn,
                                     kCGHeadInsertEventTap,
                                     kCGEventTapOptionDefault,
                                     CGEventMaskBit(kCGEventKeyDown),
                                     handleEvent, this);

  if (_tapRef == nullptr) {
    throw EventTapCreationException(::strerror(errno));
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
