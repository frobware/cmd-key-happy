-- Converts old-style cmd-key-happy.lua files to new syntax.

function convert(t)
   for key, value in pairs(t) do
      if (type(key) == "string") then
	 print(string.format("swap_cmdalt \"%s\"", key))
	 if (type(value) == "table") then
	    local exclude = value["exclude"]
	    if (exclude ~= nil) then
	       for key2, value2 in pairs(exclude) do
		  print(string.format("swap_cmdalt \"%s\" \"%s\"", key, key2))
	       end
	    end
	 end
      end
   end
end

dofile(arg[1])

if (_G["apps"]) then
   convert(apps)
end
