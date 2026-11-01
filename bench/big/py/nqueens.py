def safe(cols, c):
    n = len(cols)
    r = 1
    ok = True
    while r <= n:
        d = cols[r - 1] - c
        if d == 0:
            ok = False
        if d == (n + 1 - r):
            ok = False
        if d == (r - n - 1):
            ok = False
        r += 1
    return ok
def place(n, cols):
    if len(cols) == n:
        return 1
    total = 0
    c = 1
    while c <= n:
        if safe(cols, c):
            total += place(n, cols + [c])
        c += 1
    return total
print("nqueens(10) = " + str(place(10, [])))
