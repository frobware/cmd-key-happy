/*
 * Copyright (c) 2009, 2010 <andrew iain mcdermott via gmail>
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

/*
 * Introduced in Mac OS X version 10.4, event taps are filters used to
 * observe and alter the stream of low-level user input events in Mac OS X.
 * Event taps make it possible to monitor and filter input events from
 * several points within the system, prior to their delivery to a foreground
 * application. Event taps complement and extend the capabilities of the
 * Carbon event monitor mechanism, which allows an application to observe
 * input events delivered to other processes (see the function
 * GetEventMonitorTarget).
 */

#import <Cocoa/Cocoa.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <getopt.h>

#define NELEMENTS(A) (sizeof((A)) / sizeof((A)[0]))

static lua_State *L;
static int opt_debug, opt_parse;
static CFMachPortRef eventTapPort;

static struct glyph {
    unichar glyph;
    NSString *name;
} glyphMap[] = {
    { 0xF700, @"up" },		// NSUpArrowFunctionKey
    { 0xF701, @"down" },	// NSDownArrowFunctionKey
    { 0xF702, @"left" },	// NSLeftArrowFunctionKey
    { 0xF703, @"right" },	// NSRightArrowFunctionKey
    { 0xF704, @"F1" },		// NSF1FunctionKey
    { 0xF705, @"F2" },		// NSF2FunctionKey
    { 0xF706, @"F3" },		// NSF3FunctionKey
    { 0xF707, @"F4" },		// NSF4FunctionKey
    { 0xF708, @"F5" },		// NSF5FunctionKey
    { 0xF709, @"F6" },		// NSF6FunctionKey
    { 0xF70A, @"F7" },		// NSF7FunctionKey
    { 0xF70B, @"F8" },		// NSF8FunctionKey
    { 0xF70C, @"F9" },		// NSF9FunctionKey
    { 0xF70D, @"F10" },		// NSF10FunctionKey
    { 0xF70E, @"F11" },		// NSF11FunctionKey
    { 0xF70F, @"F12" },		// NSF12FunctionKey
    { 0xF710, @"F13" },		// NSF13FunctionKey
    { 0xF711, @"F14" },		// NSF14FunctionKey
    { 0xF712, @"F15" },		// NSF15FunctionKey
    { 0xF713, @"F16" },		// NSF16FunctionKey
    { 0xF714, @"F17" },		// NSF17FunctionKey
    { 0xF715, @"F18" },		// NSF18FunctionKey
    { 0xF716, @"F19" },		// NSF19FunctionKey
    { 0xF717, @"F20" },		// NSF20FunctionKey
    { 0xF718, @"F21" },		// NSF21FunctionKey
    { 0xF719, @"F22" },		// NSF22FunctionKey
    { 0xF71A, @"F23" },		// NSF23FunctionKey
    { 0xF71B, @"F24" },		// NSF24FunctionKey
    { 0xF71C, @"F25" },		// NSF25FunctionKey
    { 0xF71D, @"F26" },		// NSF26FunctionKey
    { 0xF71E, @"F27" },		// NSF27FunctionKey
    { 0xF71F, @"F28" },		// NSF28FunctionKey
    { 0xF720, @"F29" },		// NSF29FunctionKey
    { 0xF721, @"F30" },		// NSF30FunctionKey
    { 0xF722, @"F31" },		// NSF31FunctionKey
    { 0xF723, @"F32" },		// NSF32FunctionKey
    { 0xF724, @"F33" },		// NSF33FunctionKey
    { 0xF725, @"F34" },		// NSF34FunctionKey
    { 0xF726, @"F35" },		// NSF35FunctionKey
    { 0xF727, @"insert" },	// NSInsertFunctionKey
    { 0xF728, @"delete" },	// NSDeleteFunctionKey
    { 0xF729, @"home" },	// NSHomeFunctionKey
    { 0xF72A, @"begin" },	// NSBeginFunctionKey
    { 0xF72B, @"end" },		// NSEndFunctionKey
    { 0xF72C, @"page up" },	// NSPageUpFunctionKey
    { 0xF72D, @"page down" },	// NSPageDownFunctionKey
    { 0xF72E, @"print" },	// NSPrintScreenFunctionKey
    { 0xF72F, @"scroll lock" },	// NSScrollLockFunctionKey
    { 0xF730, @"pause" },	// NSPauseFunctionKey
    { 0xF731, @"sysreq" },	// NSSysReqFunctionKey
    { 0xF732, @"break" },	// NSBreakFunctionKey
    { 0xF733, @"reset" },	// NSResetFunctionKey
    { 0xF734, @"stop" },	// NSStopFunctionKey
    { 0xF735, @"menu" },	// NSMenuFunctionKey
    { 0xF736, @"user" },	// NSUserFunctionKey
    { 0xF737, @"system" },	// NSSystemFunctionKey
    { 0xF738, @"print" },	// NSPrintFunctionKey
    { 0xF739, @"clearline" },	// NSClearLineFunctionKey
    { 0xF73A, @"cleardpy" },	// NSClearDisplayFunctionKey
    { 0xF73B, @"insertline" },	// NSInsertLineFunctionKey
    { 0xF73C, @"deleteline" },	// NSDeleteLineFunctionKey
    { 0xF73D, @"insertchar" },	// NSInsertCharFunctionKey
    { 0xF73E, @"deletechar" },	// NSDeleteCharFunctionKey
    { 0xF73F, @"prev" },	// NSPrevFunctionKey
    { 0xF740, @"next" },	// NSNextFunctionKey
    { 0xF741, @"select" },	// NSSelectFunctionKey
    { 0xF742, @"execute" },	// NSExecuteFunctionKey
    { 0xF743, @"undo" },	// NSUndoFunctionKey
    { 0xF744, @"redo" },	// NSRedoFunctionKey
    { 0xF745, @"find" },	// NSFindFunctionKey
    { 0xF746, @"help" },	// NSHelpFunctionKey
    { 0xF747, @"modeswitch" },	// NSModeSwitchFunctionKey
    { 0x0003, @"enter" },	// NSEnterCharacter
    { 0x0008, @"backspace" },	// NSBackspaceCharacter
    { 0x0009, @"tab" },		// NSTabCharacter
    { 0x000a, @"newline" },	// NSNewlineCharacter
    { 0x000c, @"formfeed" },	// NSFormFeedCharacter
    { 0x000d, @"enter" },	// NSCarriageReturnCharacter
    { 0x0019, @"backtab" },	// NSBackTabCharacter
    { 0x007f, @"delete" },	// NSDeleteCharacter
    { 0x2028, @"linesep" },	// NSLineSeparatorCharacter
    { 0x2029, @"paragrapsep" }, // NSParagraphSeparatorCharacter
    { 0x001b, @"escape" },	// escape
    { 0x0003, @"return" },
    { 0x0020, @"space" },
};

// The set of Lua libraries available.

static const luaL_Reg lua_sandboxed_libs[] = {
    { "", luaopen_base },
    { LUA_LOADLIBNAME, luaopen_package },
    { LUA_TABLIBNAME, luaopen_table },
    { LUA_IOLIBNAME, luaopen_io },
    { LUA_STRLIBNAME, luaopen_string },
    { LUA_DBLIBNAME, luaopen_debug },
    { NULL, NULL}
};

static inline int glyphMapCmp(const void *a, const void *b)
{
    return (((struct glyph *)a)->glyph - ((struct glyph *)b)->glyph);
}

/*
 * Binary search the glyphMap map for key.
 *
 * Returns position in the map or a -number if it cannot be found.
 */
static inline int findGlyph(unichar key) {
    int first = 0;
    int upto  = NELEMENTS(glyphMap);
    const struct glyph a = { key, nil };

    while (first < upto) {
	int mid = (first + upto) / 2;
	struct glyph *b = &glyphMap[mid];
	int cmp = glyphMapCmp(&a, b);

	if (cmp < 0)
	    upto = mid;		// Repeat search in bottom half
	else if (cmp > 0)
	    first = mid + 1;	// Repeat search in top half
	else
	    return mid;		// Found it. return position
    }

    return -(first + 1);	// Failed to find key
}

static inline NSString *front_processname(void)
{
    ProcessSerialNumber psn = { 0L, 0L };

    if (GetFrontProcess(&psn) == noErr) {
	CFStringRef str;
	CopyProcessName(&psn, &str);
	return (NSString *)str;
    }

    return nil;
}

static NSMutableString *keyDownEventToString(CGEventFlags flags, NSEvent *event)
{
    NSMutableString *s = [[NSMutableString alloc] init];

    if (flags & kCGEventFlagMaskShift)
	[s appendString:@"shift-"];

    if (flags & kCGEventFlagMaskControl)
	[s appendString:@"control-"];

    if (flags & kCGEventFlagMaskAlternate)
	[s appendString:@"alt-"];

    if (flags & kCGEventFlagMaskCommand)
	[s appendString:@"cmd-"];

    if (flags & kCGEventFlagMaskSecondaryFn)
	[s appendString:@"fn-"];

    int idx = findGlyph([[event characters] characterAtIndex:0]);

    if (idx >= 0) {
	// escape special keys like "tab", "enter", etc.
	[s appendString:glyphMap[idx].name];
    } else {
	if ([event characters] != nil) {
	    [s appendString:[[event characters] lowercaseString]];
	} else {
	    [s appendString:[[event charactersIgnoringModifiers] lowercaseString]];
	}
    }

    return s;
}

static bool luaSwapKeys(CGEventFlags flags, int keyCode, NSString *keySeq)
{
    NSString *appname = front_processname();

    if (appname == nil)
	return false;

    /* the function name */
    lua_getglobal(L, "swap_keys");
    lua_newtable(L);

    lua_pushstring(L, "key_str_seq");
    lua_pushstring(L, [keySeq UTF8String]);
    lua_settable(L, -3);

    lua_pushstring(L, "appname");
    lua_pushstring(L, [appname UTF8String]);
    lua_settable(L, -3);

    lua_pushstring(L, "keycode");
    lua_pushnumber(L, keyCode);
    lua_settable(L, -3);

    lua_pushstring(L, "shift");
    lua_pushboolean(L, flags & kCGEventFlagMaskShift);
    lua_settable(L, -3);

    lua_pushstring(L, "control");
    lua_pushboolean(L, flags & kCGEventFlagMaskControl);
    lua_settable(L, -3);

    lua_pushstring(L, "alt");
    lua_pushboolean(L, flags & kCGEventFlagMaskAlternate);
    lua_settable(L, -3);

    lua_pushstring(L, "cmd");
    lua_pushboolean(L, flags & kCGEventFlagMaskCommand);
    lua_settable(L, -3);

    lua_pushstring(L, "fn");
    lua_pushboolean(L, flags & kCGEventFlagMaskSecondaryFn);
    lua_settable(L, -3);

    // Lua call: (1 arguments, 1 result).

    if (lua_pcall(L, 1, 1, 0) != 0) {
	NSLog(@"lua error: %s", lua_tostring(L, -1));
	[appname release];
	return 0;
    }

    if (!lua_isboolean(L, -1)) {
	NSLog(@"error: expected boolean value"
	      " from swap_keys(), received %s", lua_tostring(L, -1));
    }

    [appname release];

    return lua_isboolean(L, -1) && lua_toboolean(L, -1);
}

/*
 * A keyboard event handler that will (potentially) swap the cmd/alt
 * keys.  The decision to swap is based on the boolean return value
 * from the Lua function swap_keys().
 */
static CGEventRef handleEvent(CGEventTapProxy proxy, CGEventType type,
			      CGEventRef event, void *arg)
{
    CGEventFlags flags = CGEventGetFlags(event);

    if (type == kCGEventTapDisabledByTimeout) {
	NSLog(@"kCGEventTapDisabledByTimeout, Enabling Event Tap");
	CGEventTapEnable(eventTapPort, true);
	return event;
    }

    if (type == kCGEventTapDisabledByUserInput) {
	NSLog(@"kCGEventTapDisabledByUserInput, Enabling Event Tap");
	CGEventTapEnable(eventTapPort, true);
	return NULL;
    }

    // Return unless the event is cmd/alt.

    if (!((flags & kCGEventFlagMaskCommand) ||
	  (flags & kCGEventFlagMaskAlternate))) {
	return event;
    }

    // If both cmd and alt are down then don't swap.

    if ((flags & kCGEventFlagMaskCommand) &&
	(flags & kCGEventFlagMaskAlternate)) {
	return event;
    }

    NSEvent *nsevent = [NSEvent eventWithCGEvent:event];
    NSMutableString *keySeq = keyDownEventToString(flags, nsevent);
    bool swapKeys = luaSwapKeys(flags, nsevent.keyCode, keySeq);

    if (swapKeys) {
	if (flags & kCGEventFlagMaskCommand) {
	    flags &= ~kCGEventFlagMaskCommand;
	    flags |= kCGEventFlagMaskAlternate;
	} else if (flags & kCGEventFlagMaskAlternate) {
	    flags &= ~kCGEventFlagMaskAlternate;
	    flags |= kCGEventFlagMaskCommand;
	}
	CGEventSetFlags(event, flags);
    }

    [keySeq release];

    return event;
}

static int installEventTap(void)
{
    CFRunLoopSourceRef source;

    eventTapPort = CGEventTapCreate(kCGSessionEventTap,
				    kCGHeadInsertEventTap,
				    kCGEventTapOptionDefault,
				    CGEventMaskBit(kCGEventKeyDown),
				    handleEvent, NULL);


    if (eventTapPort == NULL) {
	NSLog(@"error: failed to create event tap!");
	return -1;
    }

    source = CFMachPortCreateRunLoopSource(NULL, eventTapPort, 0L);

    if (source == NULL) {
	NSLog(@"error: no event src!");
	return -1;
    }

    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    CFRelease(source);

    return 0;
}

int main(int argc, char *argv[])
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSError *error = nil;
    int filearg = 0;
      
    struct option cmd_line_opts[] = {
	{ "debug", no_argument,	      NULL, 'd' },
	{ "file",  required_argument, NULL, 'f' },
	{ "parse", no_argument,	      NULL, 'p' },
	{  NULL,   0,		      NULL, 0	}
    };

    if (!AXAPIEnabled()) {
	NSLog(@"error: enable access for assistive devices in "
	      "System Preferences -> Universal Access");
	return EXIT_FAILURE;
    }

    if ((L = lua_open()) == NULL) {
	NSLog(@"error: cannot create Lua interpreter");
	return EXIT_FAILURE;
    }
    
    int c = 0;

    while ((c = getopt_long(argc, argv, "df:p", cmd_line_opts, NULL)) != -1) {
	switch (c) {
	case 'd':
	    opt_debug = 1;
	    break;
	case 'f':
	    filearg = optind;
	    break;
	case 'p':
	    opt_parse = 1;
	    break;
	default:
	    NSLog(@"usage: cmd-key-happy [-p] [-f <filename>]");
	    return EXIT_FAILURE;
	}
    }

    NSString *scriptFile;
    
    if (filearg) {
	scriptFile = [[NSString alloc] initWithUTF8String:argv[filearg-1]];
    } else {
	scriptFile = [[NSString alloc] initWithUTF8String:"~/.cmd-key-happy.lua"];
    }
	
    // Read and evaluate Lua script.

    NSStringEncoding scriptEncoding;
    NSString *script = [NSString stringWithContentsOfFile:[scriptFile stringByExpandingTildeInPath]
					     usedEncoding:&scriptEncoding
						    error:&error];
    
    if (!script) {
	NSLog(@"error: cannot open `%@': %@", scriptFile, [error localizedFailureReason]);
	[scriptFile release];
	return EXIT_FAILURE;
    }

    [scriptFile release];
    
    // Load the reduced set of lua libraries

    for (const luaL_Reg *lib = lua_sandboxed_libs; lib->func; lib++) {
	lua_pushcfunction(L, lib->func);
	lua_pushstring(L, lib->name);
	lua_call(L, 1, 0);
    }

    if (luaL_dostring(L, [script UTF8String]) != 0) {
	NSLog(@"lua error: %s", lua_tostring(L, -1));
	return EXIT_FAILURE;
    }

    if (opt_parse)		// parse only?
	return EXIT_SUCCESS;

    if (installEventTap() != 0)
	return EXIT_FAILURE;

    // Need a sorted glyphMap; only used in the event handler.
    qsort(glyphMap, NELEMENTS(glyphMap), sizeof(glyphMap[0]), glyphMapCmp);

    [pool release];
    [[NSRunLoop currentRunLoop] run];
    
    return EXIT_SUCCESS;
}
