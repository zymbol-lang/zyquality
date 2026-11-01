const w = 250, h = 250, maxit = 100;
let inside = 0;
for (let py = 0; py < h; py++) {
  for (let px = 0; px < w; px++) {
    const cr = (3.0 * px) / w - 2.0;
    const ci = (2.0 * py) / h - 1.0;
    let zr = 0.0, zi = 0.0, it = 0;
    while (it < maxit) {
      const t = zr * zr - zi * zi + cr;
      zi = 2.0 * zr * zi + ci;
      zr = t;
      if (zr * zr + zi * zi > 4.0) break;
      it = it + 1;
    }
    if (it === maxit) inside++;
  }
}
console.log("mandelbrot inside=" + inside);
