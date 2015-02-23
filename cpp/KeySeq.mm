#include <vector>
#include <algorithm>
#include <iostream>
#include <sstream>
#include "KeySeq.hpp"

using namespace frobware;

template<typename Input, typename Output>
Output SplitKeySeq(Input first, Input last, Output out)
{
   std::string word;
   int lastc = 0;
   bool word_pending = false;

   while (first != last) {
      const int c = *first++;

      if (lastc == '-' && c == '-') {
	 word.clear();
	 word.push_back(static_cast<char>(c));
	 *out++ = word;
	 word.clear();
	 word_pending = false;
	 lastc = 0;
	 continue;
      } else if (c == '-') {
	 if (word_pending)
	    *out++ = word;
	 word.clear();
	 word_pending = false;
	 lastc = c;
	 continue;
      }

      word.push_back(static_cast<char>(c));
      word_pending = true;
      lastc = c;
   }

   if (word_pending)
      *out++ = word;

   return out;
}

KeySeq::KeySeq(const std::string& seq) : _seq(seq), _flags(0), _key()
{
   std::vector<std::string> words;

   SplitKeySeq(seq.begin(), seq.end(), std::back_inserter(words));

   for (auto&& word : words) {
      if (word == "shift")
	 _flags |= kCGEventFlagMaskShift;

      if (word == "control")
	 _flags |= kCGEventFlagMaskControl;

      if (word == "alt")
	 _flags |= kCGEventFlagMaskAlternate;

      if (word == "cmd")
	 _flags |= kCGEventFlagMaskCommand;
      
      // if (word == "alt") {
      // 	 _flags |= kCGEventFlagMaskAlternate;
      // } else if (word == "control") {
      // 	 _flags |= kCGEventFlagMaskControl;
      // } else if (word == "shift") {
      // 	 _flags |= kCGEventFlagMaskShift;
      // } else if (word == "cmd") {
      // 	 _flags |= kCGEventFlagMaskCommand;
      // }
   }

   if (words.size() > 0) {
      _key = words[words.size() - 1];
   }
}

KeySeq::KeySeq(const std::string& key, CGEventFlags flags) : _key(key), _flags(flags)
{
   if (flags & kCGEventFlagMaskShift)
      _seq += "shift-";

   if (flags & kCGEventFlagMaskControl)
      _seq += "control-";

   if (flags & kCGEventFlagMaskAlternate)
      _seq += "alt-";

   if (flags & kCGEventFlagMaskCommand)
      _seq += "cmd-";

   _seq += key;
}
