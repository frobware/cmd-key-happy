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

#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <Foundation/Foundation.h>

#include <algorithm>
#include <iostream>
#include <sstream>
#include <cstdio>
#include <cassert>
#include "ProcessList.hpp"
#include "EventTap.hpp"
#include "CmdKeyHappy.hpp"

using namespace frobware;

CmdKeyHappy* CmdKeyHappy::_instance = 0;

static const EventTypeSpec kEvents[] = {
  { kEventClassApplication, kEventAppTerminated },
  { kEventClassApplication, kEventAppFrontSwitched }
};

OSStatus CmdKeyHappy::eventHandler(EventHandlerCallRef callref,
                                   EventRef            event,
                                   void *              arg)
{
  frobware::CmdKeyHappy *ckh = static_cast<frobware::CmdKeyHappy *>(arg);
  ProcessSerialNumber psn;

  OSErr err = ::GetEventParameter(event,
                                  kEventParamProcessID,
                                  typeProcessSerialNumber,
                                  NULL,
                                  sizeof psn,
                                  NULL,
                                  &psn);

  if (err != noErr) {
    NSLog(@"GetEventParameter: %s", ::strerror(errno));
    return err;
  }

  // Note: I would have used kEventAppActivated but I'm finding a race
  // condition using this event. I tried to add the tap based on this
  // event but more often than not it would fail to create; the error
  // was typically "No such process". Adding a small delay (0.5s)
  // typically makes it work but that sucks!
  //
  // Checking for the existence of a tap or adding a tap every time an
  // app becomes the front most application seems easier and cheaper
  // than maintaining a pending set of taps to add on some timer,
  // particularly as you would want some exponential back-off if the
  // tap continues to fail to insert. tapApp() is idempotent so
  // calling it multiple times for each kEventAppFrontSwitched has a
  // very small cost.

  switch (GetEventKind(event)) {
    case kEventAppFrontSwitched: {
      ProcessInfo proc(psn);
      if (proc && ckh->isAppRegistered(proc.name()))
        ckh->tapApp(proc);
      break;
    }
    case kEventAppTerminated:
      ckh->appTerminated(psn);
      break;
  }

  return noErr;
}

CmdKeyHappy* CmdKeyHappy::Instance()
{
  if (!_instance)
    _instance = new CmdKeyHappy;

  return _instance;
}

void CmdKeyHappy::run()
{
  EventHandlerRef carbonEventsRef = NULL;

  ::InstallEventHandler(::GetApplicationEventTarget(),
                        eventHandler,
                        GetEventTypeCount(kEvents),
                        kEvents,
                        this,
                        &carbonEventsRef);

  {
    // Scope the process list so that it gets free'd before the
    // NSRunLoop starts.

    ProcessList pl;

    for (const auto& proc : pl) {
      if (isAppRegistered(proc.name())) {
        tapApp(proc);
      }
    }
  }

  [[NSRunLoop currentRunLoop] run];
}

bool CmdKeyHappy::isAppRegistered(const std::string& name) const
{
  return _appMap.find(name) != _appMap.end();
}

static bool operator<(const ProcessSerialNumber lhs, const ProcessSerialNumber rhs)
{
  assert(lhs.highLongOfPSN == 0);
  assert(rhs.highLongOfPSN == 0);
  // XXX what about the high part?
  return lhs.lowLongOfPSN < rhs.lowLongOfPSN;
}

void CmdKeyHappy::tapApp(const ProcessInfo& proc)
{
  if (_tapMap.find(proc.psn()) != _tapMap.end())
    return;			// already done!

  try {
    const auto& appIter = _appMap.find(proc.name());
    if (appIter != _appMap.end()) {
      std::cout << "Registering new EventTap for " << (*appIter).second << std::endl;
      EventTap *tap = new EventTap(proc.psn(), (*appIter).second);
      _tapMap.insert({proc.psn(), tap});
    }
  } catch (EventTapCreationException& x) {
    std::stringstream sstr;

    sstr << "error: could not create tap for: "
         << proc
         << ": "
         << x.what();

    NSLog(@"%s\n", sstr.str().c_str());
  }
}

void CmdKeyHappy::appTerminated(ProcessSerialNumber psn)
{
  const auto iter = _tapMap.find(psn);

  if (iter != _tapMap.end()) {
    _tapMap.erase(iter);
    delete (*iter).second;
  }
}

void CmdKeyHappy::registerApp(const AppSpec& app)
{
  _appMap.insert({app.name(), app});
}

