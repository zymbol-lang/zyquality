use strict; use warnings;
my $m = 20000;
my @v = (0) x $m;
for my $i (1 .. 3000) { $v[$i - 1] = $i; }
print "array_update $v[2999] " . scalar(@v) . "\n";
