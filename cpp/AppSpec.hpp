/*
 * Copyright (c) 2015 <andrew.iain.mcdermott@gmail.com>
 *
 * Source can be cloned from:
 *
 *	git://github.com/andymcd/cmd-key-happy.git
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
#include <string>
#include <iterator>
#include <set>
#include <iostream>
#include "KeySeq.hpp"

namespace frobware {
   class AppSpec {
   public:
      template <class Iterator>
      AppSpec(const std::string& name, Iterator begin, Iterator end)
	 : _name(name),
	   _exclusions(begin, end) {}

      inline const std::string name() const {
	 return _name;
      }

      inline bool isKeySequenceExcluded(const KeySeq &seq) const {
	return _exclusions.find(seq) != _exclusions.end();
      }

      friend std::ostream& operator<<(std::ostream& os, const AppSpec& obj) {
	 os << "AppSpec name=\""
	    << obj._name
	    << "\""
	    << " exclusions=[";

	 if (obj._exclusions.size() > 0) {
	    for (const auto& word : obj._exclusions) {
	       os << "\"" << word << "\"";
	    }
	 }

	 os << "]";

	 return os;
      }
   private:
      std::string _name;
      std::set<KeySeq> _exclusions;
   };
}
