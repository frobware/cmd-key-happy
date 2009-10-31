function Set(t)
   local s = {}
   for _,v in pairs(t) do s[v] = true end
   return s
end

function set_contains(t, e)
   return t[e]
end

-- The set of shortcuts we don't want to swap cmd/alt.

global_excludes = Set{ "shift-control-cmd-i",
                       "shift-control-cmd-n",
                       "shift-cmd-tab",
                       "cmd-tab",
                       "shift-cmd-n",
                       "shift-cmd-e" }

-- The set of apps we want to consider swapping keys for, with some
-- notable exclusions.

apps = {
   Terminal = { exclude = Set{ "shift-cmd-[",
                               "shift-cmd-]",
                               "cmd-w",
                               "cmd-1",
                               "cmd-2",
                               "cmd-3",
                               "cmd-t",
                               "cmd-n",
                               } },
   Eclipse  = { exclude = {} }
}

-- Return true to swap cmd/alt, otherwis false.

function swap_keys(t)
   --   for i,v in pairs(t) do print(i,v) end
   if set_contains(global_excludes, t.key_str_seq) then return false end
   if not apps[t.appname] then return false end
   local excludes = apps[t.appname]["exclude"]
   if set_contains(excludes, t.key_str_seq) then
      return false
   end
   return true
end

