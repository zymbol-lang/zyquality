from _t import *
t = now(); result = 0
for _ in range(10):
    a, b = 0, 1
    for _ in range(39): a, b = b, a + b
    result = b
print("N1_fib40_loop:      result=%d" % result, "", el(t))
t = now(); grand = 0
for n in range(1, 50001):
    x = n; ds = 0
    while x > 0: ds += x % 10; x = x // 10
    grand += ds
print("N2_digit_sum:       total=%d" % grand, "", el(t))
t = now(); pc = 0
for n in range(2, 5001):
    ip = True; d = 2
    while ip and d * d <= n:
        if n % d == 0: ip = False
        d += 1
    if ip: pc += 1
print("N3_primes_5k:       count=%d" % pc, "", el(t))
t = now(); total = 0
for i in range(1, 200001): total += (i * i) % 1000
print("N4_modular_sq:      total=%d" % total, "", el(t))
t = now(); fz = bz = fb_c = 0
for i in range(1, 1000001):
    fb = i % 15 == 0
    f = (not fb) and i % 3 == 0
    b = (not fb) and i % 5 == 0
    if fb: fb_c += 1
    elif f: fz += 1
    elif b: bz += 1
print("N5_fizzbuzz_1M:     fizz=%d buzz=%d fb=%d" % (fz, bz, fb_c), "", el(t))
t = now(); a_arr = []; b_arr = []
for i in range(1, 5001): a_arr.append(i)
for i in range(1, 5001): b_arr.append(5001 - i)
dot = 0
for i in range(5000): dot += a_arr[i] * b_arr[i]
print("N6_dot_product:     result=%d" % dot, "", el(t))
