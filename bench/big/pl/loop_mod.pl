use strict; use warnings;
my $s = 0;
for my $i (1 .. 10000000) { $s = ($s + ($i * $i) % 1000) % 1000003; }
print "loop_mod = $s\n";
