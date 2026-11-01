const n = 150;
const a = [], b = [];
for (let i = 0; i < n; i++)
  for (let j = 0; j < n; j++) { a.push((i * j) % 10); b.push((i + j) % 7); }
let chk = 0;
for (let i = 0; i < n; i++) {
  for (let j = 0; j < n; j++) {
    let s = 0;
    for (let k = 0; k < n; k++) s = s + a[i * n + k] * b[k * n + j];
    chk = (chk + s * (i + j + 1)) % 1000003;
  }
}
console.log("matmul chk = " + chk);
