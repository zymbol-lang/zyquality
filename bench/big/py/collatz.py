best = 0
bestn = 0
for n in range(1, 60001):
    x = n
    steps = 0
    while x != 1:
        if x % 2 == 0:
            x = x // 2
        else:
            x = 3 * x + 1
        steps += 1
    if steps > best:
        best = steps
        bestn = n
print("collatz " + str(bestn) + " " + str(best))
