def classify(x):
    if 0 <= x <= 9:
        return 1
    if 10 <= x <= 49:
        return 2
    if 50 <= x <= 99:
        return 3
    return 4
acc = 0
for i in range(1, 3000001):
    acc += classify(i % 150)
print("match_loop " + str(acc))
