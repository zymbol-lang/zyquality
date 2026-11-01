from functools import cmp_to_key
n = 4000
v = []
x = 12345
for _ in range(n):
    x = (x * 1103 + 12345) % 1000003
    v.append(x)
r = sorted(v, key=cmp_to_key(lambda p, q: -1 if p < q else (1 if p > q else 0)))
print("sort_cmp_4k " + str(r[0]) + " " + str(r[n // 2 - 1]) + " " + str(r[n - 1]))
