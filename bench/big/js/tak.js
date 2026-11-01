function tak(x, y, z) {
  if (y < x) return tak(tak(x - 1, y, z), tak(y - 1, z, x), tak(z - 1, x, y));
  return z;
}
let r = 0;
for (let i = 0; i < 3; i++) r = tak(24, 16, 8);
console.log("tak(24,16,8) x3 = " + r);
