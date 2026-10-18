use strict; use warnings;
sub tak { my ($x, $y, $z) = @_; return $y < $x ? tak(tak($x - 1, $y, $z), tak($y - 1, $z, $x), tak($z - 1, $x, $y)) : $z; }
my $r = 0;
for (1 .. 3) { $r = tak(24, 16, 8); }
print "tak(24,16,8) x3 = $r\n";
