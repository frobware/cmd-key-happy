import cmdswap

#CmdSwap.Register("foo", 'cmd-c', 'cmd-v', 'cmd-w')
cmdswap.Register("terminal", "bar")
cmdswap.Register("terminal", "bar")
cmdswap.Register("terminal", "bar")
cmdswap.Register("terminal", "bar")
cmdswap.Register("terminal", "bar")
cmdswap.Register("xcode", "foo")
cmdswap.Register("xcode", "bar")

if cmdswap.IsAppRegistered("terminal"):
    cmdswap.Dump()
