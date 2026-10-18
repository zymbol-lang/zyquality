<?php
$w = 250; $h = 250; $maxit = 100;
$inside = 0;
for ($py = 0; $py < $h; $py++) {
    for ($px = 0; $px < $w; $px++) {
        $cr = (3.0 * $px) / $w - 2.0;
        $ci = (2.0 * $py) / $h - 1.0;
        $zr = 0.0; $zi = 0.0; $it = 0;
        while ($it < $maxit) {
            $t = $zr * $zr - $zi * $zi + $cr;
            $zi = 2.0 * $zr * $zi + $ci;
            $zr = $t;
            if ($zr * $zr + $zi * $zi > 4.0) break;
            $it = $it + 1;
        }
        if ($it == $maxit) $inside++;
    }
}
echo "mandelbrot inside=$inside\n";
