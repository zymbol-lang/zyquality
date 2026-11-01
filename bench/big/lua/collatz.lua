local best, bestn = 0, 0
for n = 1, 60000 do
  local x, steps = n, 0
  while x ~= 1 do
    if x % 2 == 0 then x = x // 2 else x = 3 * x + 1 end
    steps = steps + 1
  end
  if steps > best then best = steps; bestn = n end
end
print("collatz " .. bestn .. " " .. best)
