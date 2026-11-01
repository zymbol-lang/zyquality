local function classify(x)
  if 0 <= x and x <= 9 then return 1 end
  if 10 <= x and x <= 49 then return 2 end
  if 50 <= x and x <= 99 then return 3 end
  return 4
end
local acc = 0
for i = 1, 3000000 do acc = acc + classify(i % 150) end
print("match_loop " .. acc)
