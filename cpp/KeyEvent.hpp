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

#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>
#include <string>

namespace frobware {

class KeyEvent {
 public:
  typedef unsigned long long ID;
  
  KeyEvent(CGEventFlags flags, CGKeyCode keyCode)
      : _flags(flags),
        _keyCode(keyCode),
        _keyID(0)
  {
    _keyID |= (_flags & kCGEventFlagMaskShift) << 1;
    _keyID |= (_flags & kCGEventFlagMaskControl) << 2;
    _keyID |= (_flags & kCGEventFlagMaskAlternate) << 3;
    _keyID |= (_flags & kCGEventFlagMaskCommand) << 4;
    _keyID |= (_flags & kCGEventFlagMaskSecondaryFn) << 5;
    _keyID |= (_keyCode << 6);
  }

  KeyEvent(const CGEventRef event)
      : KeyEvent(::CGEventGetFlags(event),
                 ::CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode)) {}

  inline CGEventFlags flags() const {
    return _flags;
  }

  inline CGKeyCode keyCode() const {
    return _keyCode;
  }
  
  inline ID keyCodeWithModifiers() const {
    return _keyID;
  }

  inline bool isAltPressed() const {
    return _flags & kCGEventFlagMaskAlternate;
  }

  inline bool isCmdPressed() const {
    return _flags & kCGEventFlagMaskCommand;
  }

  inline bool operator==(const KeyEvent& other) const {
    return _keyID == other._keyID;
  }

  static std::string KeyStringSequence(CGEventRef event);
  static CGEventRef SwapCmdAndAlt(CGEventRef event, CGEventFlags flags);
 private:
  CGEventFlags _flags = 0;
  CGKeyCode _keyCode = 0;
  ID _keyID = 0;
};

}
