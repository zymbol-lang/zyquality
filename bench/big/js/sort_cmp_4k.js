const n = 4000;
const v = [];
let x = 12345;
for (let i = 0; i < n; i++) {
  x = (x * 1103 + 12345) % 1000003;
  v.push(x);
}
const r = v.slice().sort((p, q) => (p < q ? -1 : (p > q ? 1 : 0)));
console.log("sort_cmp_4k " + r[0] + " " + r[Math.floor(n / 2) - 1] + " " + r[n - 1]);
