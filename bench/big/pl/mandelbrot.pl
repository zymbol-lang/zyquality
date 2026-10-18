use strict; use warnings;
my ($w, $h, $maxit) = (250, 250, 100);
my $inside = 0;
for my $py (0 .. $h - 1) {
    for my $px (0 .. $w - 1) {
        my $cr = (3.0 * $px) / $w - 2.0;
        my $ci = (2.0 * $py) / $h - 1.0;
        my ($zr, $zi, $it) = (0.0, 0.0, 0);
        while ($it < $maxit) {
            my $t = $zr * $zr - $zi * $zi + $cr;
            $zi = 2.0 * $zr * $zi + $ci;
            $zr = $t;
            last if $zr * $zr + $zi * $zi > 4.0;
            $it = $it + 1;
        }
        $inside++ if $it == $maxit;
    }
}
print "mandelbrot inside=$inside\n";
