use strict; use warnings;
my $n = 150;
my (@a, @b);
for my $i (0 .. $n - 1) { for my $j (0 .. $n - 1) { push @a, ($i * $j) % 10; push @b, ($i + $j) % 7; } }
my $chk = 0;
for my $i (0 .. $n - 1) {
    for my $j (0 .. $n - 1) {
        my $s = 0;
        for my $k (0 .. $n - 1) { $s = $s + $a[$i * $n + $k] * $b[$k * $n + $j]; }
        $chk = ($chk + $s * ($i + $j + 1)) % 1000003;
    }
}
print "matmul chk = $chk\n";
