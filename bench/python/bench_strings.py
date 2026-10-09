from _t import *
t = now(); s = ""
for i in range(0, 2001): s = s + "x"
print("string_concat: len =", len(s), "", el(t))
t = now(); csv = "one,two,three,four,five,six,seven,eight,nine,ten"; total_parts = 0
for i in range(0, 1001):
    parts = csv.split(','); total_parts += len(parts)
print("split_ops: total_parts =", total_parts, "", el(t))
t = now(); long_str = "abcdefghijklmnopqrstuvwxyz"; slice_chars = 0
for i in range(0, 2001):
    sl = long_str[0:14]; slice_chars += len(sl)
print("slice_ops: slice_chars =", slice_chars, "", el(t))
t = now(); words = ["hello", "world", "zymbol", "lang", "symbolic", "unicode"]; total_len = 0
for i in range(1, 5001):
    w = words[(i - 1) % 6]; total_len += len(w)
print("length_ops: total_len =", total_len, "", el(t))
t = now(); sentence = "a man a plan a canal panama"; total_a = 0
for _ in range(0, 501):
    for ch in sentence:
        if ch == 'a': total_a += 1
print("char_iter: total_a =", total_a, "", el(t))
t = now(); haystack = "the quick brown fox jumps over the lazy dog"; needles = ['a', 'e', 'i', 'o', 'u', 'z', 'x', 'q']; hits = 0
for i in range(1, 2001):
    needle = needles[(i - 1) % 8]
    if needle in haystack: hits += 1
print("string_contains:", hits, "hits", "", el(t))
t = now(); prefix = "Zymbol"; suffix = "lang"; build_total = 0
for i in range(1, 2001):
    token = prefix + "-" + suffix + "-" + str(i); build_total += len(token)
print("multi_token_build: total_chars =", build_total, "", el(t))
t = now(); csv2 = "alpha,beta,gamma,delta,epsilon,zeta,eta,theta,iota,kappa"; unfused_len = 0
for _ in range(0, 1001):
    parts2 = csv2.split(','); lengths2 = list(map(lambda w: len(w), parts2)); unfused_len += len(lengths2)
print("split_map_unfused: total =", unfused_len, "", el(t))
t = now(); fused_len = 0
for _ in range(0, 1001):
    lengths = list(map(lambda w: len(w), csv2.split(','))); fused_len += len(lengths)
print("split_map_fused:   total =", fused_len, "", el(t))
