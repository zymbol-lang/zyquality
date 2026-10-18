use strict; use warnings;
my ($best, $bestn) = (0, 0);
for my $n (1 .. 60000) {
    my $x = $n; my $steps = 0;
    while ($x != 1) {
        if ($x % 2 == 0) { $x = $x / 2; } else { $x = 3 * $x + 1; }
        $steps++;
    }
    if ($steps > $best) { $best = $steps; $bestn = $n; }
}
print "collatz $bestn $best\n";
