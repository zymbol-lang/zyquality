use strict; use warnings;
my $n = 600000;
my @v; my $x = 12345;
for (1 .. $n) { $x = ($x * 1103 + 12345) % 1000003; push @v, $x; }
my @r = sort { $a <=> $b } @v;
print "sort_builtin $r[0] $r[299999] $r[$n - 1]\n";
