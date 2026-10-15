def tak(x, y, z):
    if y < x:
        return tak(tak(x - 1, y, z), tak(y - 1, z, x), tak(z - 1, x, y))
    return z
r = 0
for _ in range(3):
    r = tak(24, 16, 8)
print("tak(24,16,8) x3 = " + str(r))
