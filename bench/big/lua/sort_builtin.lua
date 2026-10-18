local n = 600000
local v, x = {}, 12345
for i = 1, n do
  x = (x * 1103 + 12345) % 1000003
  v[i] = x
end
local r = {}
for i = 1, n do r[i] = v[i] end
table.sort(r)
print("sort_builtin " .. r[1] .. " " .. r[300000] .. " " .. r[n])
