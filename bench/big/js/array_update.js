const m = 20000;
const v = new Array(m).fill(0);
for (let i = 1; i <= 3000; i++) v[i - 1] = i;
console.log("array_update " + v[2999] + " " + v.length);
