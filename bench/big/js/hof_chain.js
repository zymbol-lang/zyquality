const nums = [];
for (let i = 1; i <= 100000; i++) nums.push(i);
let total = 0;
for (let r = 0; r < 25; r++) {
  const sq = nums.map(x => x * x);
  const ev = sq.filter(x => x % 3 === 0);
  const s = ev.reduce((acc, x) => acc + x, 0);
  total += s;
}
console.log("hof_chain total = " + total);
