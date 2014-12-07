/*
 * Copyright (c) 2013 <andrew.iain.mcdermott@gmail.com>
 *
 * Source can be cloned from:
 *
 *      git://github.com/andymcd/cmd-key-happy.git
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

#include <string>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <sstream>
#include <cctype>
#include <getopt.h>
#include "CmdKeyHappy.hpp"
#include "KeySeq.hpp"
#include <sys/stat.h>

using namespace frobware;

// ShellWords: tokenize input, splitting on [space].  Note: words with
// spaces can be accommodated by quoting them.  Other than that this
// is a very very basic shell-word-like-tokenizer.

template<typename Input, typename Output>
Output ShellWords(Input first, Input last, Output out)
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

    word.push_back(static_cast<char>(c));
    word_pending = true;
  }

  if (quote && word_pending)
    throw std::runtime_error("quoted word not terminated");

  if (word_pending)
    *out++ = word;

  return out;
}

static bool parseConfigurationFile(const std::string& filename)
{
  CmdKeyHappy *c = CmdKeyHappy::Instance();

  size_t lineno = 0;
  std::ifstream ifs(filename);
  std::string line;

  while (std::getline(ifs, line)) {
    lineno++;

    if (line.size() == 0 || line[0] == '#')
      continue;

    std::vector<std::string> words;

    try {
      ShellWords(line.begin(), line.end(), std::back_inserter(words));
      for (auto i2 = words.begin(); i2 != words.end(); i2++) {
        KeySeq keySeq(*i2);
      }
    } catch (std::runtime_error& x) {
      std::cerr << filename
                << ":"
                << lineno
                << " error: "
                << x.what()
                << std::endl;
      return false;
    }

    if (words.size() > 1 && words[0] == "swap_cmdalt") {
      c->registerProcess(words[1], words.begin() + 2, words.end());
    } else if (words.size() > 0) {
      std::cerr << filename
                << ":"
                << lineno
                << " warning: unknown command `"
                << words[0]
                << "'"
                << std::endl;
    }
  }

  return true;
}

int main(int argc, char* argv[])
{
  bool parseOnly = false;
  bool verbose = false;

  struct option cmd_line_opts[] = {
    { "help",    no_argument, NULL, 'h' },
    { "parse",   no_argument, NULL, 'p' },
    { "verbose", no_argument, NULL, 'v' },
    { NULL,      0,           NULL, 0 }
  };

  int c = 0;

  while ((c = ::getopt_long(argc, argv, "hpv", cmd_line_opts, NULL)) != -1) {
    switch (c) {
      case 'v':
        verbose = true;
        break;
      case 'p':
        parseOnly = true;
        break;
      case 'h':
      default:
        std::cerr << "usage: cmd-key-happy [-p] [-v] [<FILENAME>]" << std::endl;
        return EXIT_FAILURE;
    }
  }

  argc -= optind;

  std::stringstream configFilename;

  if (argc > 0) {
    configFilename << argv[optind];
  } else {
    configFilename << ::getenv("HOME")
                   << "/"
                   << ".cmd-key-happy.rc";
  }

  struct stat sbuf;

  if (stat(configFilename.str().c_str(), &sbuf) < 0) {
    std::cerr << "error: cannot open: `"
              << configFilename.str()
              << "': "
              << strerror(errno)
              << std::endl;
    return EXIT_FAILURE;
  }

  if (verbose) {
    std::cout << "Reading from: " << configFilename.str() << std::endl;
  }

  if (!parseConfigurationFile(configFilename.str().c_str()))
    return EXIT_FAILURE;

  if (parseOnly)
    return EXIT_SUCCESS;

  bool accessibilityEnabled;

#if MAC_OS_X_VERSION_MAX_ALLOWED <= MAC_OS_X_VERSION_10_8
  accessibilityEnabled = AXAPIEnabled();
  if (!accessibilityEnabled) {
    CFUserNotificationDisplayNotice(0,
                                    kCFUserNotificationStopAlertLevel,
                                    NULL, NULL, NULL,
                                    CFSTR("Enable Access for Assistive Devices"),
                                    CFSTR("This setting can be enabled in System Preferences via the Universal Access preferences pane"),
                                    CFSTR("Ok"));
  }
#else
  NSDictionary *options = @{(id)kAXTrustedCheckOptionPrompt : @YES};
  accessibilityEnabled = AXIsProcessTrustedWithOptions((CFDictionaryRef)options);
#endif

  if (!accessibilityEnabled) {
    NSLog(@"error: accessibility not enabled for cmd-key-happy!");
    return EXIT_FAILURE;
  }

  try {
    CmdKeyHappy::Instance()->run();
    return EXIT_SUCCESS;
  } catch (std::exception& x) {
    std::cerr << "fatal error: " << x.what() << std::endl;
  }

  return EXIT_FAILURE;
}
