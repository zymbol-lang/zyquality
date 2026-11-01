local m = 20000
local v = {}
for i = 1, m do v[i] = 0 end
for i = 1, 3000 do v[i] = i end
print("array_update " .. v[3000] .. " " .. #v)
