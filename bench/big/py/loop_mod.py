s = 0
for i in range(1, 10000001):
    s = (s + (i * i) % 1000) % 1000003
print("loop_mod = " + str(s))
