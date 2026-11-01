from functools import reduce
nums = list(range(1, 100001))
total = 0
for _ in range(25):
    sq = list(map(lambda x: x * x, nums))
    ev = list(filter(lambda x: x % 3 == 0, sq))
    s = reduce(lambda acc, x: acc + x, ev, 0)
    total += s
print("hof_chain total = " + str(total))
