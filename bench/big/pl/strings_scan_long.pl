use strict; use warnings;
my $unit = "the quick brown fox jumps over the lazy dog ";
my $text = "";
for (1 .. 2000) { $text = $text . $unit; }
my $vow = 0;
for (1 .. 5) {
    for my $ch (split //, $text) {
        $vow++ if $ch eq 'a';
        $vow++ if $ch eq 'e';
        $vow++ if $ch eq 'o';
    }
}
print "strings_scan_long len=" . length($text) . " vow=$vow\n";
