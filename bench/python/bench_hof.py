from _t import *
from functools import reduce, cmp_to_key
nums = list(range(1, 10001))
add = lambda acc, x: acc + x
t = now(); total = 0
for _ in range(20): total += len(list(map(lambda x: x * x, nums)))
print("H1_map_square:      reps=20 len=%d" % total, "", el(t))
t = now(); total = 0
for _ in range(20): total += len(list(filter(lambda x: x % 7 == 0, nums)))
print("H2_filter_mod7:     reps=20 len=%d" % total, "", el(t))
t = now(); total = 0
for _ in range(50): total += reduce(add, nums, 0)
print("H3_reduce_sum:      reps=50 result=%d" % total, "", el(t))
t = now(); total = 0
for _ in range(10): total += reduce(add, filter(lambda x: x % 2 == 0, nums), 0)
print("H4_filter_reduce:   reps=10 result=%d" % total, "", el(t))
t = now(); total = 0
for _ in range(10): total += reduce(add, map(lambda x: x * x, nums), 0)
print("H5_map_reduce:      reps=10 result=%d" % total, "", el(t))
t = now()
for _ in range(10): asc = sorted(nums)
print("H6_sort_asc:        reps=10 len=%d" % len(asc), "", el(t))
t = now()
for _ in range(5): desc = sorted(nums, reverse=True)
print("H7_sort_desc:       reps=5 first=%d" % desc[0], "", el(t))
t = now(); small = nums[0:500]
for _ in range(3): custom = sorted(small, key=cmp_to_key(lambda a, b: -1 if a < b else 1))
print("H8_sort_custom:     reps=3 first=%d" % custom[0], "", el(t))
t = now(); total = 0
for _ in range(5):
    p = list(map(lambda x: x * 2, filter(lambda x: x % 3 == 0, nums)))
    total += len(sorted(p, reverse=True))
print("H9_filter_map_sort: reps=5 len=%d" % total, "", el(t))
