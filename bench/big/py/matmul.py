n = 150
a = []
b = []
for i in range(n):
    for j in range(n):
        a.append((i * j) % 10)
        b.append((i + j) % 7)
chk = 0
for i in range(n):
    for j in range(n):
        s = 0
        for k in range(n):
            s = s + a[i * n + k] * b[k * n + j]
        chk = (chk + s * (i + j + 1)) % 1000003
print("matmul chk = " + str(chk))
