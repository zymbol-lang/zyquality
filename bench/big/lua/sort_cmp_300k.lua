local n = 300000
local v, x = {}, 12345
for i = 1, n do
  x = (x * 1103 + 12345) % 1000003
  v[i] = x
end
local r = {}
for i = 1, n do r[i] = v[i] end
table.sort(r, function(p, q) return p < q end)
print("sort_cmp_300k " .. r[1] .. " " .. r[n // 2] .. " " .. r[n])
