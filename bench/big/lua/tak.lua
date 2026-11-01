local function tak(x, y, z)
  if y < x then return tak(tak(x - 1, y, z), tak(y - 1, z, x), tak(z - 1, x, y)) end
  return z
end
local r = 0
for _ = 1, 3 do r = tak(24, 16, 8) end
print("tak(24,16,8) x3 = " .. r)
