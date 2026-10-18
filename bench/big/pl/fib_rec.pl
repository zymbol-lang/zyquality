use strict; use warnings;
sub fib { my $n = shift; return $n if $n <= 1; return fib($n - 1) + fib($n - 2); }
print "fib(34) = " . fib(34) . "\n";
