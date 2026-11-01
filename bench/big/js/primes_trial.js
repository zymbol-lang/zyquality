const primes = [];
let count = 0;
for (let n = 2; n <= 300000; n++) {
  let isp = true, k = 1;
  while (k <= count) {
    const p = primes[k - 1];
    if (p * p > n) break;
    if (n % p === 0) { isp = false; break; }
    k++;
  }
  if (isp) { primes.push(n); count++; }
}
console.log("primes " + count + " " + primes[count - 1]);
