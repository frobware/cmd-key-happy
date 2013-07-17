#!/usr/bin/env python

import shlex

class SyntaxError(Exception):
    def __init__(self, msg):
        self.msg = msg
    def __str__(self):
        return self.msg

def gen_tokenizer(args):
    for a in args:
        yield a

def cmdswap_fn(args):
    tokenizer = gen_tokenizer(args)
    word = tokenizer.next()
    if word != '-appname':
        raise SyntaxError("expected \"-appname\"; got \"" + word + "\"")
    appname = tokenizer.next()
    if not apps.has_key(appname):
        apps[appname] = { 'swapall': False, 'exclude': [] }
    app = apps[appname]
    try:
        word = tokenizer.next()
        if word == '-swap-all':
            app['swapall'] = True
        elif word == '-exclude':
            for word in tokenizer:
                app['exclude'].append(word)
        else:
            raise SyntaxError("unexpected command \"" + word + "\"")
    except StopIteration:
        return

def command_handler(name):
    try:
        return cmds[name]
    except KeyError:
        return None             # XXX fixme

cmds = { 'cmdswap': cmdswap_fn }
apps = {}

with open("ckh.txt") as file:
    lineno = 0
    for line in file:
        line = line.rstrip()
        lineno = lineno + 1
        if len(line) == 0 or line.startswith('#'):
            continue
        words = shlex.split(line, comments=True)
        handler = command_handler(words[0])
        if handler is None:
            print "{0}: warning: unknown command: {1}".format(lineno, words[0])
        else:
            handler(words[1:])

print apps
