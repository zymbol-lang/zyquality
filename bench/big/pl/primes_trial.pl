use strict; use warnings;
my @primes; my $count = 0;
for my $n (2 .. 300000) {
    my $isp = 1; my $k = 1;
    while ($k <= $count) {
        my $p = $primes[$k - 1];
        last if $p * $p > $n;
        if ($n % $p == 0) { $isp = 0; last; }
        $k++;
    }
    if ($isp) { push @primes, $n; $count++; }
}
print "primes $count $primes[$count - 1]\n";
