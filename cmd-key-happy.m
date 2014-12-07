/*
 * Copyright (c) 2009, 2010, 2013 <andrew iain mcdermott via gmail>
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

#include <AvailabilityMacros.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <IOKit/hidsystem/IOLLEvent.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <getopt.h>
#include <assert.h>

#define NELEMENTS(A) (sizeof((A)) / sizeof((A)[0]))

static lua_State *L;
static int opt_debug, opt_parse;
static CFMachPortRef eventTapPort;
static NSMapTable *keySequenceToStrMapping;

struct unicharMap {
    unichar uc;
    NSString *name;
};

#define FIRST_IN_GRP1	0xF700
#define LAST_IN_GRP1	0xF747

struct unicharMap escapeCharGrp1[] = {
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
};

struct unicharMap escapeCharGrp2[] = {
    { 0x0003, @"enter" },	// NSEnterCharacter
    { 0x0008, @"backspace" },	// NSBackspaceCharacter
    { 0x0009, @"tab" },		// NSTabCharacter
    { 0x000a, @"newline" },	// NSNewlineCharacter
    { 0x000c, @"formfeed" },	// NSFormFeedCharacter
    { 0x000d, @"return" },	// NSCarriageReturnCharacter
    { 0x0019, @"tab" },		// NSBackTabCharacter
    { 0x007f, @"delete" },	// NSDeleteCharacter
    { 0x2028, @"linesep" },	// NSLineSeparatorCharacter
    { 0x2029, @"paragrapsep" }, // NSParagraphSeparatorCharacter
    { 0x001b, @"escape" },	// escape
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

static inline NSString *isEscapble(unichar key)
{
    int i;
    
    if (key >= FIRST_IN_GRP1 && key <= LAST_IN_GRP1) {
	i = (LAST_IN_GRP1 - FIRST_IN_GRP1) - (LAST_IN_GRP1 - key);
	assert(i >= 0 && i < (int)NELEMENTS(escapeCharGrp1));
	return escapeCharGrp1[i].name;
    } else {
	for (i = 0; i < (int)NELEMENTS(escapeCharGrp2); i++) {
	    if (key == escapeCharGrp2[i].uc) {
		return escapeCharGrp2[i].name;
	    }
	}
    }

    return nil;
}

/*
 * Translate the virtual keycode to a character representation.  This
 * function does not handle the modifier keys.  It also translates
 * certain keys to more human readable forms (e.g., "tab", "space",
 * "up").  Because no modifiers are considered a "shift-n" will return
 * "n", not "N".
 */
NSString *translateKeycode(CGKeyCode keyCode, CGEventRef event)
{
    static UInt32           deadKeyState        = 0;
    TISInputSourceRef       currentKeyboard;
    CFDataRef               uchr                = NULL;
    UInt32                  modifierKeyState    = 0;
    UInt32                  keyboardType;
    UniCharCount            actualStringLength  = 0;
    UniChar                 unicodeString[5];
    const UCKeyboardLayout *keyboardLayout;
    CGEventSourceRef        source;
    
    if ((source = CGEventCreateSourceFromEvent(event)) == NULL)
        return nil;

    currentKeyboard = TISCopyCurrentKeyboardInputSource();
    uchr = (CFDataRef) TISGetInputSourceProperty(currentKeyboard, kTISPropertyUnicodeKeyLayoutData);

    if (uchr == nil) {
        CFRelease(source);
        return nil;
    }

    keyboardLayout = (const UCKeyboardLayout *)CFDataGetBytePtr(uchr);
    keyboardType = CGEventSourceGetKeyboardType(source);
    
    CFRelease(source);

    assert(currentKeyboard);
    assert(uchr);
    assert(keyboardLayout);

    if (keyboardLayout == NULL) {
        NSLog(@"no keyboard layout");
	return nil;
    }

    OSStatus status = UCKeyTranslate(keyboardLayout,
                                     keyCode,
				     kUCKeyActionDisplay,
                                     modifierKeyState,
                                     keyboardType,
				     kUCKeyTranslateNoDeadKeysBit,
                                     &deadKeyState,
                                     NELEMENTS(unicodeString),
                                     &actualStringLength,
                                     unicodeString);

    if (status != noErr)
        return nil;

    if (actualStringLength < 1)
        return nil;

    NSEvent *nsevent = [NSEvent eventWithCGEvent:event];
    NSString *input = [nsevent charactersIgnoringModifiers];
    
    if (input != nil) {
	NSString *replacement = isEscapble([input characterAtIndex:0]);
	if (replacement != nil)
	    return replacement;
    }
    
    return [NSString stringWithCharacters:unicodeString length:actualStringLength];
}

static NSString *keyDownEventToString(CGEventFlags flags, CGKeyCode keyCode, CGEventRef event)
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

    // According to:
    //   http://lists.apple.com/archives/quartz-dev/2008/Jan/msg00019.html
    //
    // the kCGEventFlagMaskSecondaryFn is not a modifier key so we no
    // longer treat it as such.

    NSString *keyStr = translateKeycode(keyCode, event);

    if (keyStr != nil)
	[s appendString:keyStr];

    return s;
}

static bool luaSwapKeys(const CGEventRef event)
{
    CGEventFlags flags = CGEventGetFlags(event);
    CGKeyCode keyCode = CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    NSRunningApplication *app = [[NSWorkspace sharedWorkspace] frontmostApplication];
    NSString *appname = [app localizedName];
    unsigned long kid = 0;

    if (appname == nil)
	return false;

    kid |= (flags & kCGEventFlagMaskShift) << 1;
    kid |= (flags & kCGEventFlagMaskControl) << 2;
    kid |= (flags & kCGEventFlagMaskAlternate) << 3;
    kid |= (flags & kCGEventFlagMaskCommand) << 4;
    kid |= (flags & kCGEventFlagMaskSecondaryFn) << 5;
    kid |= keyCode << 6;
    assert(kid > 0);

    NSString *keySeq = [keySequenceToStrMapping objectForKey:(id)kid];

    if (!keySeq) {
	keySeq = keyDownEventToString(flags, keyCode, event);
	[keySequenceToStrMapping setObject:keySeq forKey:(id)kid];
    }

    /* the function name */
    lua_getglobal(L, "swap_keys");

    /* the table to pass to swap_keys(). */
    lua_getglobal(L, "sWaP_kEyS_t");

    lua_pushstring(L, "key_str_seq");
    lua_pushstring(L, [keySeq UTF8String]);
    lua_settable(L, -3);

    lua_pushstring(L, "appname");
    lua_pushstring(L, [[app localizedName] UTF8String]);
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
	return 0;
    }

    if (!lua_isboolean(L, -1)) {
	NSLog(@"error: expected boolean value"
	      " from swap_keys(), received %s", lua_tostring(L, -1));
    }

    bool result = lua_toboolean(L, -1);

    lua_pop(L, 1);		/* pop returned value */

    return result;
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

    if (luaSwapKeys(event)) {
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
	}
	CGEventSetFlags(event, flags);
    }

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

    keySequenceToStrMapping = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaqueMemory|NSPointerFunctionsIntegerPersonality
						    valueOptions:NSMapTableStrongMemory];

    if ((L = luaL_newstate()) == NULL) {
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

    lua_createtable(L, 10, 10);
    lua_setglobal(L, "sWaP_kEyS_t");

    if (opt_parse)		// parse only?
	return EXIT_SUCCESS;

    BOOL accessibilityEnabled;

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

    if (installEventTap() != 0)
        return EXIT_FAILURE;

    [[NSRunLoop currentRunLoop] run];
    [pool release];
    
    return EXIT_SUCCESS;
}
