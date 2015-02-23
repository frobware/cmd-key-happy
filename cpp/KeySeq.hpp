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

#include <utility>
#include <string>

namespace frobware {

class KeySeq
{
 public:
  explicit KeySeq(const std::string& key, CGEventFlags flags);
  explicit KeySeq(const std::string& seq);

  inline CGEventFlags flags() const {
    return _flags;
  }

  inline const std::string key() const {
    return _key;
  }

  inline bool operator<(const KeySeq& rhs) const {
    return std::tie(_key, _flags) < std::tie(rhs._key, rhs._flags);
  }

  friend std::ostream& operator<<(std::ostream& os, const KeySeq& obj) {
    os << "flags=" << obj._flags << ", key='" << obj._key << "'";
    return os;
  }

 private:
  KeySeq() = delete;
  std::string _seq;
  std::string _key;
  CGEventFlags _flags = 0;
};

}
