from _t import *
def classify(x):
    if x == 1: return "one"
    if x == 2: return "two"
    if x == 3: return "three"
    if x == 4: return "four"
    if x == 5: return "five"
    return "other"
def grade(s):
    if 90 <= s <= 100: return "A"
    if 80 <= s <= 89: return "B"
    if 70 <= s <= 79: return "C"
    if 60 <= s <= 69: return "D"
    if 0 <= s <= 59: return "F"
    return "?"
def quadrant(x, y):
    if 0 <= x <= 100: return "Q1" if 0 <= y <= 100 else "Q4"
    return "Q2" if 0 <= y <= 100 else "Q3"
t = now(); hits = 0
for i in range(0, 50001):
    if classify((i % 6) + 1) != "other": hits += 1
print("value_match:", hits, "non-other hits", "", el(t))
t = now(); a = 0
for i in range(0, 50001):
    if grade(i % 101) == "A": a += 1
print("range_match:", a, "A-grades", "", el(t))
t = now(); q = 0
for i in range(0, 20001):
    if quadrant(i % 200, i % 150) == "Q1": q += 1
print("nested_match:", q, "Q1 hits", "", el(t))
