#pragma once

#include <stdexcept>
#include <string>
#include <cctype>

namespace frobware {
template<typename Input, typename Output>
Output shellwords(Input first, Input last, Output out)
    throw(std::runtime_error)
{
  std::string word;
  bool word_pending = false;
  int quote = 0;

  while (first != last) {
    const int c = *first++;

    if (std::isspace(c) && !quote) {
      if (word_pending)
        *out++ = word;
      word.clear();
      word_pending = false;
      continue;
    }

    if (c == '"') {
      quote = 1 - quote;
      continue;
    }

    word.push_back(c);
    word_pending = true;
  }

  if (quote && word_pending)
    throw std::runtime_error("quoted word not terminated");

  if (word_pending)
    *out++ = word;

  return out;
}
}
