primes = []
count = 0
for n in range(2, 300001):
    isp = True
    k = 1
    while k <= count:
        p = primes[k - 1]
        if p * p > n:
            break
        if n % p == 0:
            isp = False
            break
        k += 1
    if isp:
        primes.append(n)
        count += 1
print("primes " + str(count) + " " + str(primes[count - 1]))
