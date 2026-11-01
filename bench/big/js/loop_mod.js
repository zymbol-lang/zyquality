let s = 0;
for (let i = 1; i <= 10000000; i++) s = (s + (i * i) % 1000) % 1000003;
console.log("loop_mod = " + s);
