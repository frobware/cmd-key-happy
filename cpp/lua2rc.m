/*
 * Copyright (c) 2015 <andrew iain mcdermott via gmail>
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

#include <AvailabilityMacros.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>
#import <IOKit/hidsystem/IOLLEvent.h>

#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
#include <getopt.h>

static lua_State *L;

static void stackdump_g(const char *ident, int lineno, lua_State* l)
{
  int i;
  int top = lua_gettop(l);

  printf("[%s:%d] LUA STACK: depth=%d\n", ident ? ident : __func__, lineno, top);

  for (i = 1; i <= top; i++) {
    switch (lua_type(l, -i)) {
    case LUA_TSTRING:
      printf("\t%d: string: '%s' (%p)\n", -i, lua_tostring(l, -i), lua_topointer(l, -i));
      break;
    case LUA_TBOOLEAN:
      printf("\t%d: boolean %s (%p)\n", -i, lua_toboolean(l, -i) ? "true" : "false", lua_topointer(l, -i));
      break;
    case LUA_TNUMBER:
      printf("\t%d: number: %g (%p))\n", -i, lua_tonumber(l, -i), lua_topointer(l, -i));
      break;
    default:
      printf("\t%d: %s (%p)\n", -i, lua_typename(l, lua_type(l, -i)), lua_topointer(l, -i));
      break;
    }
  }
  printf("\n");  /* end the listing */
}

static NSMutableDictionary *parse_apps_table(lua_State *L, int index)
{
  NSMutableDictionary *apps = [[NSMutableDictionary alloc] init];

  if (!lua_istable(L, index)) {
    NSLog(@"error: expected table received %s", lua_typename(L, lua_type(L, index)));
    abort();
  }

  lua_pushnil(L);  /* first key */

  while (lua_next(L, -2) != 0) {
    if (lua_type(L, -2) != LUA_TSTRING)
      continue;
    NSString *appName = [NSString stringWithUTF8String:lua_tostring(L, -2)];
    NSMutableSet *excludes = [[NSMutableSet alloc] init];
    if (lua_type(L, -1) == LUA_TTABLE) {
      lua_getfield(L, -1, "exclude");
      if (lua_type(L, -1) == LUA_TTABLE) {
	lua_pushnil(L);  /* first key */
	while (lua_next(L, -2) != 0) {
	  [excludes addObject:[NSString stringWithUTF8String:lua_tostring(L, -2)]];
	  // removes 'value'; keeps 'key' for next iteration
	  lua_pop(L, 1);
	}
      }
      lua_pop(L, 1);
    }
    [apps setObject:excludes forKey:appName];
    // removes 'value'; keeps 'key' for next iteration
    lua_pop(L, 1);
  }

  lua_pop(L, 1);

  return apps;
}

int main(int argc, char *argv[])
{
  int filearg = 0;

  struct option cmd_line_opts[] = {
    { "file",  required_argument, NULL, 'f' },
    {  NULL,   0,		      NULL, 0	}
  };

  if ((L = luaL_newstate()) == NULL) {
    NSLog(@"error: cannot create Lua interpreter");
    return EXIT_FAILURE;
  }

  luaL_openlibs(L);

  int c = 0;

  while ((c = getopt_long(argc, argv, "f:", cmd_line_opts, NULL)) != -1) {
    switch (c) {
    case 'f':
      filearg = optind;
      break;
    default:
      NSLog(@"usage: lua2rc [-f <filename>]");
      return EXIT_FAILURE;
    }
  }

  NSString *scriptFile;

  if (filearg) {
    scriptFile = [[NSString alloc] initWithUTF8String:argv[filearg-1]];
  } else {
    scriptFile = [[NSString alloc] initWithUTF8String:"~/.cmd-key-happy.lua"];
  }

  if (luaL_loadfile(L, [[scriptFile stringByExpandingTildeInPath] UTF8String]) != 0) {
    NSLog(@"lua error: %s", lua_tostring(L, -1));
    return EXIT_FAILURE;
  }

  if (lua_pcall(L, 0, 0, 0)) { /* PRIMING RUN. FORGET THIS AND YOU'RE TOAST */
    NSLog(@"lua error: %s", lua_tostring(L, -1));
    return EXIT_FAILURE;
  }

  lua_getglobal(L, "apps");
  
  NSMutableDictionary *apps = parse_apps_table(L, -1);

  printf ("apps: %lu\n", [apps count]);

  NSLog(@"apps: %@", apps);

  return EXIT_SUCCESS;
}
