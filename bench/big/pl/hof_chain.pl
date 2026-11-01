use strict; use warnings;
use List::Util qw(reduce);
my @nums = (1 .. 100000);
my $total = 0;
for (1 .. 25) {
    my @sq = map { $_ * $_ } @nums;
    my @ev = grep { $_ % 3 == 0 } @sq;
    my $s = reduce { $a + $b } 0, @ev;
    $total += $s;
}
print "hof_chain total = $total\n";
