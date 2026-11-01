use strict; use warnings;
my $unit = "the quick brown fox jumps over the lazy dog ";
my $text = "";
for (1 .. 100) { $text = $text . $unit; }
my $vow = 0;
for (1 .. 200) {
    for my $ch (split //, $text) {
        $vow++ if $ch eq 'a';
        $vow++ if $ch eq 'e';
        $vow++ if $ch eq 'o';
    }
}
print "strings_scan_short len=" . length($text) . " vow=$vow\n";
