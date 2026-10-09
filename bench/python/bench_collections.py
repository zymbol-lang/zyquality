from _t import *
from functools import reduce
t = now(); arr = []
for i in range(0, 3000): arr.append(i)
print("array_build: len =", len(arr), "", el(t))
t = now(); base = list(range(1, 501)); found = 0
for i in range(1, 2001):
    if (i % 500) in base: found += 1
print("array_contains:", found, "hits", "", el(t))
t = now(); src = list(range(1, 101)); s = 0
for i in range(0, 1000):
    sl = src[0:50]; s += len(sl)
print("slice_ops: slice_sum =", s, "", el(t))
data = list(range(0, 5000))
t = now(); d = list(map(lambda x: x * 2, data)); print("map_hof: output len =", len(d), "", el(t))
t = now(); e = list(filter(lambda x: x % 2 == 0, data)); print("filter_hof: evens =", len(e), "", el(t))
t = now(); tot = reduce(lambda acc, x: acc + x, data, 0); print("reduce_hof: sum =", tot, "", el(t))
t = now(); rem = list(range(0, 500))
for _ in range(0, 200): rem = rem[1:]
print("remove_ops: remaining len =", len(rem), "", el(t))
