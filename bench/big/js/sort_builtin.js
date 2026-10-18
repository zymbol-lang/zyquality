const n = 600000;
const v = [];
let x = 12345;
for (let i = 0; i < n; i++) {
  x = (x * 1103 + 12345) % 1000003;
  v.push(x);
}
const r = Float64Array.from(v).sort();
console.log("sort_builtin " + r[0] + " " + r[299999] + " " + r[n - 1]);
