use strict; use warnings;
sub safe {
    my ($cols, $c) = @_;
    my $n = scalar(@$cols);
    my $r = 1; my $ok = 1;
    while ($r <= $n) {
        my $d = $cols->[$r - 1] - $c;
        $ok = 0 if $d == 0;
        $ok = 0 if $d == ($n + 1 - $r);
        $ok = 0 if $d == ($r - $n - 1);
        $r++;
    }
    return $ok;
}
sub place {
    my ($n, $cols) = @_;
    return 1 if scalar(@$cols) == $n;
    my $total = 0; my $c = 1;
    while ($c <= $n) {
        $total += place($n, [@$cols, $c]) if safe($cols, $c);
        $c++;
    }
    return $total;
}
print "nqueens(10) = " . place(10, []) . "\n";
