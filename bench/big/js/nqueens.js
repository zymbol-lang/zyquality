function safe(cols, c) {
  const n = cols.length;
  let r = 1, ok = true;
  while (r <= n) {
    const d = cols[r - 1] - c;
    if (d === 0) ok = false;
    if (d === (n + 1 - r)) ok = false;
    if (d === (r - n - 1)) ok = false;
    r++;
  }
  return ok;
}
function place(n, cols) {
  if (cols.length === n) return 1;
  let total = 0, c = 1;
  while (c <= n) {
    if (safe(cols, c)) total += place(n, [...cols, c]);
    c++;
  }
  return total;
}
console.log("nqueens(10) = " + place(10, []));
