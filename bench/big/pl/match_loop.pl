use strict; use warnings;
sub classify {
    my $x = shift;
    return 1 if 0 <= $x && $x <= 9;
    return 2 if 10 <= $x && $x <= 49;
    return 3 if 50 <= $x && $x <= 99;
    return 4;
}
my $acc = 0;
for my $i (1 .. 3000000) { $acc += classify($i % 150); }
print "match_loop $acc\n";
