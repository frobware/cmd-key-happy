/*
 * Copyright (c) 2009 <andrew iain mcdermott via gmail >
 *
 * Source can be cloned from:
 *
 * git://github.com/aim-stuff/cmd-key-happy.git
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
 * GetEventMonitorTarget)."
 */

#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <syslog.h>
#include <stdarg.h>
#include <getopt.h>
#include <unistd.h>
#include <sys/param.h>
#include <sys/types.h>
#include <sys/event.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>

#include <Carbon/Carbon.h>

#define UNUSED_ARG(x)           (void) x
#define ARRAY_SIZE(A)           (sizeof((A)) / sizeof((A)[0]))

int debug_opt = 0;
const char *progname  = "cmd-key-happy";

struct cmd_key_happy_ctx {
    char                rcfile[PATH_MAX];
    lua_State          *L;
    int                 rcfile_vnode_fd;
    int                 event_tap_is_passive;
    CFMutableStringRef  modifier_str; /* keyboard modifier flags */
    CFMutableStringRef  keycode_str; /* keyboard character string */
    int                 kq;          /* kqueue descriptor */
};

static const struct {
    const char *name;
    unsigned short glyph;
} name2glyph_map[] = {
    { "backspace", 0x08 },
    { "backtab",   0x19 },
    { "delete",    0x7f },
    { "down",      0x1f },
    { "end",       0x04 },
    { "enter",     0x0d },
    { "escape",    0x1b },
    { "home",      0x01 },
    { "left",      0x1c },
    { "page down", 0x0c },
    { "page up",   0x0b },
    { "return",    0x03 },
    { "right",     0x1d },
    { "space",     0x20 },
    { "tab",       0x09 },
    { "up",        0x1e },
};

/* The set of Lua libraries available. */

static const luaL_Reg lua_sandboxed_libs[] = {
    {"", luaopen_base},
    {LUA_LOADLIBNAME, luaopen_package},
    {LUA_TABLIBNAME, luaopen_table},
    {LUA_IOLIBNAME, luaopen_io},
    {LUA_STRLIBNAME, luaopen_string},
    {LUA_DBLIBNAME, luaopen_debug},
    {NULL, NULL}
};

void fatal(const char *fmt, ...)
{
    if (fmt != NULL) {
        va_list argp;
        va_start(argp, fmt);
        vsyslog(LOG_ERR, fmt, argp);
        va_end(argp);
    }
    exit(EXIT_FAILURE);
}

void quit_run_loop(const char *fmt, ...)
{
    if (fmt != NULL) {
        va_list argp;
        va_start(argp, fmt);
        vsyslog(LOG_ERR, fmt, argp);
        va_end(argp);
    }
    CFRunLoopStop(CFRunLoopGetCurrent());
}

void error(const char *fmt, ...)
{
    if (fmt == NULL) return;
    va_list argp;
    va_start(argp, fmt);
    vsyslog(LOG_ERR, fmt, argp);
    va_end(argp);
}

void warn(const char *fmt, ...)
{
    if (fmt == NULL) return;
    va_list argp;
    va_start(argp, fmt);
    vsyslog(LOG_WARNING, fmt, argp);
    va_end(argp);
}

void debug(const char *fmt, ...)
{
    if (!debug_opt || fmt == NULL) return;
    va_list argp;
    va_start(argp, fmt);
    vsyslog(LOG_DEBUG, fmt, argp);
    va_end(argp);
}

void info(const char *fmt, ...)
{
    if (fmt == NULL) return;
    va_list argp;
    va_start(argp, fmt);
    vsyslog(LOG_INFO, fmt, argp);
    va_end(argp);
}

int cfstr2cstr(CFStringRef str, char *buf, size_t nbuf)
{
    CFIndex l = CFStringGetMaximumSizeForEncoding(CFStringGetLength(str),
                                                  CFStringGetSystemEncoding()) + 1;

    if (((size_t)l) >= nbuf) return -1;
    CFStringGetCString(str, buf, l, kCFStringEncodingASCII);
    return 0;
}

/*
 * Populate BUF with the current front application by name.
 */
OSStatus front_processname(char *buf, size_t n)
{
    CFStringRef         str;
    ProcessSerialNumber psn    = { 0L, 0L };
    OSStatus            status = GetFrontProcess(&psn);

    if (status != noErr) return status;
    CopyProcessName(&psn, &str);
    cfstr2cstr(str, buf, n);
    CFRelease(str);
    return status;
}

ssize_t flags2str(CGEventFlags flags, CFMutableStringRef s)
{
    CFIndex mark = CFStringGetLength(s);

    if (flags & kCGEventFlagMaskShift) {
        CFStringAppendCString(s, "shift-", kCFStringEncodingASCII);
    }
    if (flags & kCGEventFlagMaskControl) {
        CFStringAppendCString(s, "control-", kCFStringEncodingASCII);
    }
    if (flags & kCGEventFlagMaskAlternate) {
        CFStringAppendCString(s, "alt-", kCFStringEncodingASCII);
    }
    if (flags & kCGEventFlagMaskCommand) {
        CFStringAppendCString(s, "cmd-", kCFStringEncodingASCII);
    }
    if (flags & kCGEventFlagMaskSecondaryFn) {
        CFStringAppendCString(s, "fn-", kCFStringEncodingASCII);
    }
    return CFStringGetLength(s) - mark;
}

int eval_lua_script(struct cmd_key_happy_ctx *ctx)
{
    int rc = 0;
    assert(ctx->L);
    info("reading `%s'", ctx->rcfile);
    if (luaL_dofile(ctx->L, ctx->rcfile) != 0) {
        error("%s", lua_tostring(ctx->L, -1));
        rc = -1;
    }
    return rc;
}

/*
 * Translate the virtual keycode to a character representation.  This
 * function does not handle the modifier keys.  It also translates
 * certain keys to more human readable forms (e.g., "tab", "space",
 * "up").  Because no modifiers are considered a "shift-n" will return
 * "n", not "N".
 */
OSStatus translate_keycode(CGKeyCode keycode, CGEventSourceRef source, CFMutableStringRef result)
{
    TISInputSourceRef       currentKeyboard;
    CFDataRef               uchr                = NULL;
    UInt16                  keyAction           = kUCKeyActionDisplay;
    UInt32                  modifierKeyState    = 0;
    OptionBits              keyTranslateOptions = kUCKeyTranslateNoDeadKeysBit;
    UInt32                  deadKeyState        = 0;
    UInt32                  keyboardType;
    UniCharCount            actualStringLength  = 0;
    UniChar                 unicodeString[8];
    const UCKeyboardLayout *keyboardLayout;

    currentKeyboard = TISCopyCurrentKeyboardInputSource();
    uchr = (CFDataRef) TISGetInputSourceProperty(currentKeyboard, kTISPropertyUnicodeKeyLayoutData);
    keyboardLayout = (const UCKeyboardLayout *)CFDataGetBytePtr(uchr);
    keyboardType = CGEventSourceGetKeyboardType(source);

    assert(currentKeyboard);
    assert(uchr);
    assert(keyboardLayout);

    if (keyboardLayout == NULL)
        fatal("no keyboard layout");

    OSStatus status = UCKeyTranslate(keyboardLayout,
                                     keycode,
                                     keyAction,
                                     modifierKeyState,
                                     keyboardType,
                                     keyTranslateOptions,
                                     &deadKeyState,
                                     ARRAY_SIZE(unicodeString),
                                     &actualStringLength,
                                     unicodeString);

    if (status != noErr)
        return status;

    if (actualStringLength < 1)
        return noErr;

    for (size_t i = 0; i < ARRAY_SIZE(name2glyph_map); i++) {
        if (name2glyph_map[i].glyph == unicodeString[0]) {
            CFStringAppendCString(result, name2glyph_map[i].name, kCFStringEncodingASCII);
            return noErr;
        }
    }

    CFStringAppendCharacters(result, unicodeString, actualStringLength);
    return noErr;
}

/*
 * A keyboard event handler that will (potentially) swap the cmd/alt
 * keys.  The decision to swap is based on the boolean return value
 * from the Lua function swap_keys().
 */

CGEventRef handle_keyboard_event(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *arg)
{
    struct cmd_key_happy_ctx *ctx   = (struct cmd_key_happy_ctx *)arg;
    CGEventSourceRef          source;
    CGKeyCode                 keycode;
    CGEventFlags              flags = CGEventGetFlags(event);
    OSStatus                  status;

    UNUSED_ARG(proxy);
    UNUSED_ARG(type);

    if (!((flags & kCGEventFlagMaskCommand) || (flags & kCGEventFlagMaskAlternate))) {
        return event;
    }

    /* If both cmd and option are down then don't swap. */

    if ((flags & kCGEventFlagMaskCommand) && (flags & kCGEventFlagMaskAlternate)) {
        return event;
    }
    
    /* For calls through to Lua. */
    char appname[1024] = { '\0' };
    char key_str_seq[1024] = { '\0' };

    /* Replace previous content. */
    CFStringPad(ctx->modifier_str, NULL, 0, 0);
    CFStringPad(ctx->keycode_str, NULL, 0, 0);

    if ((status = front_processname(appname, sizeof(appname))) != noErr) {
        error("cannot get process name: %s (%s)",
              GetMacOSStatusErrorString(status), GetMacOSStatusCommentString(status));
        return event;
    }
    if ((source = CGEventCreateSourceFromEvent(event)) == NULL)
        return event;

    flags = CGEventGetFlags(event);
    keycode = (CGKeyCode) CGEventGetIntegerValueField(event, kCGKeyboardEventKeycode);
    status = translate_keycode(keycode, source, ctx->keycode_str);

    if (status != noErr) {
        error("cannot translate keycode=%d: %s (%s)",
              keycode, GetMacOSStatusErrorString(status), GetMacOSStatusCommentString(status));
        CFRelease(source);
        return event;
    } else if (CFStringGetLength(ctx->keycode_str) < 1) {
        CFRelease(source);
        return event;
    }

    CFRelease(source);
    flags2str(flags, ctx->modifier_str);
    CFStringAppend(ctx->modifier_str, ctx->keycode_str);

    if (cfstr2cstr(ctx->modifier_str, key_str_seq, sizeof(key_str_seq)) != 0)
        return event;

    assert(ctx->L);

    /* the function name */
    lua_getglobal(ctx->L, "swap_keys");
    lua_newtable(ctx->L);

    lua_pushstring(ctx->L, "key_str_seq");
    lua_pushstring(ctx->L, key_str_seq);
    lua_settable(ctx->L, -3);

    lua_pushstring(ctx->L, "appname");
    lua_pushstring(ctx->L, appname);
    lua_settable(ctx->L, -3);

    lua_pushstring(ctx->L, "keycode");
    lua_pushnumber(ctx->L, keycode);
    lua_settable(ctx->L, -3);

    lua_pushstring(ctx->L, "shift");
    lua_pushboolean(ctx->L, flags & kCGEventFlagMaskShift);
    lua_settable(ctx->L, -3);

    lua_pushstring(ctx->L, "control");
    lua_pushboolean(ctx->L, flags & kCGEventFlagMaskControl);
    lua_settable(ctx->L, -3);

    lua_pushstring(ctx->L, "alt");
    lua_pushboolean(ctx->L, flags & kCGEventFlagMaskAlternate);
    lua_settable(ctx->L, -3);

    lua_pushstring(ctx->L, "cmd");
    lua_pushboolean(ctx->L, flags & kCGEventFlagMaskCommand);
    lua_settable(ctx->L, -3);

    lua_pushstring(ctx->L, "fn");
    lua_pushboolean(ctx->L, flags & kCGEventFlagMaskSecondaryFn);
    lua_settable(ctx->L, -3);

    /* ctx->L call: (1 arguments, 1 result) */
    if (lua_pcall(ctx->L, 1, 1, 0) != 0) {
        error("%s", lua_tostring(ctx->L, -1));
        return event;
    }
    if (!lua_isboolean(ctx->L, -1)) {
        error("expected boolean value from swap_keys(), received %s", lua_tostring(ctx->L, -1));
        return event;
    }
    if (!ctx->event_tap_is_passive && lua_toboolean(ctx->L, -1)) {
        if (flags & kCGEventFlagMaskCommand) {
            flags &= ~kCGEventFlagMaskCommand;
            flags |= kCGEventFlagMaskAlternate;
            debug("will swap cmd/alt");
        } else if (flags & kCGEventFlagMaskAlternate) {
            flags &= ~kCGEventFlagMaskAlternate;
            flags |= kCGEventFlagMaskCommand;
            debug("will swap alt/cmd");
        }
        CGEventSetFlags(event, flags);
    }
    return event;
}

/*
 * Called from the runloop when the process receives a SIGTERM or SIGINT.
 */
void kqueue_event_handler(CFFileDescriptorRef fdref, CFOptionFlags callBackTypes, void *info)
{
#pragma unused(callBackTypes)

    struct cmd_key_happy_ctx *ctx     = (struct cmd_key_happy_ctx *)info;
    int                       kq      = CFFileDescriptorGetNativeDescriptor(fdref);
    struct timespec           timeout = { 0, 0 };

    assert(kq >= 0);
    assert(callBackTypes == kCFFileDescriptorReadCallBack);

    while (true) {
        struct kevent ke;
        int rc = kevent(kq, NULL, 0, &ke, 1, &timeout);

        if (rc == -1 && errno == EINTR) {
            error("Interrupted kevent call!");
            continue;
        } else if (rc == -1) {
            fatal("kevent(): ", strerror(errno));
        } else if (rc == 0) {
            break;              /* no more events */
        } else {
            assert(rc > 0);
            if (ke.filter == EVFILT_SIGNAL && (ke.ident == SIGTERM || ke.ident == SIGINT)) {
                debug("quitting on %s", (ke.ident == SIGTERM) ? "SIGTERM" : "SIGINT");
                CFRunLoopStop(CFRunLoopGetCurrent());
            } else if (ke.filter == EVFILT_VNODE) {
                if (ke.fflags & NOTE_EXTEND || ke.fflags & NOTE_WRITE) {
                    assert(ke.udata == ctx);
                    eval_lua_script(ctx);
                }
            } else {
                error("unexpected kqueue filter: %d", ke.filter);
                break;
            }
        }
    }

    /* reinstall callback. */
    CFFileDescriptorEnableCallBacks(fdref, kCFFileDescriptorReadCallBack);
}

void install_lua_script_change_handler(struct cmd_key_happy_ctx *ctx)
{
    struct kevent kev;

    if (ctx->kq == -1) {
        if ((ctx->kq = kqueue()) == -1)
            fatal("kqueue(): %s", strerror(errno));
    }
    assert(ctx->kq >= 0);

    ctx->rcfile_vnode_fd = open(ctx->rcfile, O_EVTONLY, 0);

    if (ctx->rcfile_vnode_fd == -1)
        fatal("cannot open `%s': %s", ctx->rcfile, strerror(errno));

    EV_SET(&kev, ctx->rcfile_vnode_fd, EVFILT_VNODE,    /* watch for file modifications */
           EV_ADD | EV_ENABLE | EV_CLEAR | EV_ERROR,
           NOTE_RENAME | NOTE_WRITE | NOTE_DELETE | NOTE_EXTEND, 0, ctx);

    if (kevent(ctx->kq, &kev, 1, NULL, 0, NULL) == -1)
        fatal("kevent(): %s", strerror(errno));

    CFFileDescriptorContext context = { 0, (void *)ctx, NULL, NULL, NULL };
    CFFileDescriptorRef     kqref;
    CFRunLoopSourceRef      source;

    kqref = CFFileDescriptorCreate(kCFAllocatorDefault, ctx->kq, false, kqueue_event_handler, &context);
    source = CFFileDescriptorCreateRunLoopSource(kCFAllocatorDefault, kqref, 0);
    CFFileDescriptorEnableCallBacks(kqref, kCFFileDescriptorReadCallBack);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    CFRelease(kqref);
    CFRelease(source);
}

void install_event_tap(struct cmd_key_happy_ctx *ctx)
{
    CFMachPortRef port;
    CFRunLoopSourceRef source;

    port = CGEventTapCreate(kCGSessionEventTap,
                            kCGHeadInsertEventTap,
                            kCGEventTapOptionDefault,
                            (CGEventMaskBit(kCGEventKeyDown) |
                             CGEventMaskBit(kCGEventFlagsChanged)), handle_keyboard_event, ctx);

    if (port == NULL)
        fatal("failed to create event tap!");

    if ((source = CFMachPortCreateRunLoopSource(NULL, port, 0L)) == NULL)
        fatal("no event src!");

    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    CFRelease(port);
    CFRelease(source);
}

void install_signal_handlers(struct cmd_key_happy_ctx *ctx)
{
    CFFileDescriptorContext context = { 0, (void *)ctx, NULL, NULL, NULL };
    sig_t sigErr;
    CFFileDescriptorRef kqRef;
    CFRunLoopSourceRef kqSource;
    struct kevent kev[2];

    /*
     * Ignore SIGTERM and SIGINT.Even though we 've ignored the signal,
     * the kqueue will still see it.
     */

    sigErr = signal(SIGTERM, SIG_IGN);
    assert(sigErr != SIG_ERR);
    sigErr = signal(SIGINT, SIG_IGN);
    assert(sigErr != SIG_ERR);

    /*
     * Create a kqueue and configure it to listen for the SIGTERM signal.
     */

    if (ctx->kq == -1) {
        if ((ctx->kq = kqueue()) == -1)
            fatal("kqueue(): %s", strerror(errno));
    }
    assert(ctx->kq >= 0);

    memset(kev, 0, sizeof(kev));
    EV_SET(&kev[0], SIGINT, EVFILT_SIGNAL, EV_ADD | EV_RECEIPT, 0, 0, NULL);
    EV_SET(&kev[1], SIGTERM, EVFILT_SIGNAL, EV_ADD | EV_RECEIPT, 0, 0, NULL);

    if (kevent(ctx->kq, kev, 2, NULL, 0, NULL) == -1)
        fatal("kevent(): %s", strerror(errno));

    kqRef = CFFileDescriptorCreate(NULL, ctx->kq, true, kqueue_event_handler, &context);
    assert(kqRef != NULL);

    kqSource = CFFileDescriptorCreateRunLoopSource(NULL, kqRef, 0);
    assert(kqSource != NULL);

    CFRunLoopAddSource(CFRunLoopGetCurrent(), kqSource, kCFRunLoopDefaultMode);
    CFFileDescriptorEnableCallBacks(kqRef, kCFFileDescriptorReadCallBack);

    CFRelease(kqSource);
    CFRelease(kqRef);
}

void cleanup(struct cmd_key_happy_ctx *ctx)
{
    if (ctx->L) {
        lua_close(ctx->L);
        ctx->L = NULL;
    }
    (void)close(ctx->kq);
    (void)close(ctx->rcfile_vnode_fd);
    if (ctx->modifier_str)
        CFRelease(ctx->modifier_str);
    if (ctx->keycode_str)
        CFRelease(ctx->keycode_str);
}

int main(int argc, char *argv[])
{
    ProcessSerialNumber psn = { 0L, 0L };
    OSStatus err = GetCurrentProcess(&psn);
    assert(err == noErr);

    struct cmd_key_happy_ctx ctx = { "", NULL, -1, 0, NULL, NULL, -1 };

    struct option cmd_line_opts[] = {
        { "debug",   no_argument,       NULL, 'd' },
        { "file",    required_argument, NULL, 'f' },
        { "passive", required_argument, NULL, 'p' },
        {  NULL,     0,                 NULL, 0   }
    };

    /* Default rcfile. */

    assert(getenv("HOME") != NULL);

    snprintf(ctx.rcfile, sizeof(ctx.rcfile), "%s/.%s.lua", getenv("HOME"), progname);

    int ch;

    while ((ch = getopt_long(argc, argv, "df:p", cmd_line_opts, NULL)) != -1) {
        switch (ch) {
        case 'd':
            debug_opt = 1;
            break;
        case 'f':
            snprintf(ctx.rcfile, sizeof(ctx.rcfile), "%s", optarg);
            break;
        case 'p':
            ctx.event_tap_is_passive = 1;
            break;
        default:
            fatal("usage: [-d] [-f=<filename.lua>]");
        }
    }

    argc += optind;
    argv += optind;

    if (debug_opt)
        setlogmask(LOG_UPTO(LOG_DEBUG));
    else
        setlogmask(LOG_UPTO(LOG_INFO));

    openlog(progname, LOG_CONS | LOG_PID | LOG_PERROR, LOG_USER);

    if (!AXAPIEnabled())
        fatal("enable access for assistive devices");

    if (access(ctx.rcfile, 0644) != 0)
        fatal("cannot access `%s': %s", ctx.rcfile, strerror(errno));

    ctx.modifier_str = CFStringCreateMutable(kCFAllocatorDefault, 0);
    ctx.keycode_str = CFStringCreateMutable(kCFAllocatorDefault, 0);

    if (ctx.modifier_str == NULL || ctx.keycode_str == NULL)
        fatal("cannot create mutable strings!");

    if ((ctx.L = lua_open()) == NULL)
        fatal("cannot create Lua interpreter");

    /* Load the reduced set of lua libraries. */

    for (const luaL_Reg * lib = lua_sandboxed_libs; lib->func; lib++) {
        lua_pushcfunction(ctx.L, lib->func);
        lua_pushstring(ctx.L, lib->name);
        lua_call(ctx.L, 1, 0);
    }

    /* Evaluate user script. */

    if (eval_lua_script(&ctx) != 0)
        fatal("%s", lua_tostring(ctx.L, -1));

    install_event_tap(&ctx);
    install_lua_script_change_handler(&ctx);
    install_signal_handlers(&ctx);
    CFRunLoopRun();
    cleanup(&ctx);
    closelog();
    debug("bye!");
    return EXIT_SUCCESS;
}
