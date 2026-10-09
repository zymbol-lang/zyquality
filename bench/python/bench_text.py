from _t import *
from functools import cmp_to_key
t = now(); total_len = 0; names = ["Alice", "Bob", "Carol", "Dave", "Eve"]
for i in range(1, 5001):
    name = names[(i - 1) % 5]; score = i % 100
    line = f"User {name} scored {score} points in round {i}"; total_len += len(line)
print("T1_template_build:  total=%d" % total_len, "", el(t))
t = now(); words = ["apple", "banana", "cherry", "date", "elderberry", "fig", "grape"]; total_len = 0
for _ in range(1000):
    result = ""
    for i in range(1, 8):
        if i > 1: result = result + ","
        result = result + words[i - 1]
    total_len += len(result)
print("T2_join_sim:        total=%d" % total_len, "", el(t))
t = now(); corpus = "the quick brown fox jumps over the lazy dog and the cat sat on the mat by the tree"; short_total = long_total = 0
for _ in range(1000):
    short = list(filter(lambda w: len(w) <= 3, corpus.split(' ')))
    long_ = list(filter(lambda w: len(w) > 3, corpus.split(' ')))
    short_total += len(short); long_total += len(long_)
print("T3_word_buckets:    short=%d long=%d" % (short_total, long_total), "", el(t))
t = now(); items = ["banana", "apple", "fig", "elderberry", "date", "cherry", "grape", "avocado", "kiwi", "mango"]
cmpf = cmp_to_key(lambda a, b: -1 if len(a) < len(b) else 1)
by_len = sorted(items, key=cmpf)
for _ in range(499): by_len = sorted(items, key=cmpf)
print("T4_sort_by_len:     first=%s last=%s" % (by_len[0], by_len[9]), "", el(t))
t = now(); text = "one two three one two four five three six one two three four"
for _ in range(200):
    tokens = text.split(' '); sorted_tokens = sorted(tokens)
uniq_count = 0; prev = ""
for tok in sorted_tokens:
    if tok != prev: uniq_count += 1; prev = tok
print("T5_sort_dedup:      unique=%d" % uniq_count, "", el(t))
t = now(); total = 0; log = "ERROR: timeout at 192.168.1.1 port 8080 after 30 seconds"
for _ in range(500):
    cleaned = log.replace("ERROR: ", ""); cleaned = cleaned.replace(".", " ")
    total += len(cleaned.split(' '))
print("T6_transform_pipe:  total=%d" % total, "", el(t))
