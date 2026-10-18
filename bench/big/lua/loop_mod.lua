local s = 0
for i = 1, 10000000 do s = (s + (i * i) % 1000) % 1000003 end
print("loop_mod = " .. s)
