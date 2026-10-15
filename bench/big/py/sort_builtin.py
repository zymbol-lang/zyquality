n = 600000
v = []
x = 12345
for _ in range(n):
    x = (x * 1103 + 12345) % 1000003
    v.append(x)
r = sorted(v)
print("sort_builtin " + str(r[0]) + " " + str(r[299999]) + " " + str(r[n - 1]))
