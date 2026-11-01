m = 20000
v = [0] * m
for i in range(1, 3001):
    v[i - 1] = i
print("array_update " + str(v[2999]) + " " + str(len(v)))
