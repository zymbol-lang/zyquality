use strict; use warnings;
my $n = 300000;
my @v; my $x = 12345;
for (1 .. $n) { $x = ($x * 1103 + 12345) % 1000003; push @v, $x; }
my @r = sort { $a < $b ? -1 : ($a > $b ? 1 : 0) } @v;
print "sort_cmp_300k $r[0] " . $r[int($n / 2) - 1] . " $r[$n - 1]\n";
