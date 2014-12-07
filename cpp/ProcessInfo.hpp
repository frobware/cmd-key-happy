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

#import <AppKit/AppKit.h>
#include <string>
#include <ostream>
#include "ScopedCF.hpp"

namespace frobware {

class ProcessInfo {
 public:
  ProcessInfo(ProcessSerialNumber psn);
  ~ProcessInfo() {}

  inline pid_t pid() const {
    return _pid;
  }

  inline ProcessSerialNumber psn() const {
    return _psn;
  }

  inline const std::string& name() const {
    return _name;
  }

  inline operator bool() const {
    return _pid != -1;
  }

  friend std::ostream& operator<<(std::ostream& os, const ProcessInfo& obj) {
    os << "app="
       << obj._name
       << " pid="
       << obj._pid
       << " psn="
       <<  obj._psn.highLongOfPSN
       <<  "."
       <<  obj._psn.lowLongOfPSN;
    return os;
  }
 private:
  pid_t _pid;
  std::string _name;
  ProcessSerialNumber _psn;
};

}
