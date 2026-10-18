<?php
$unit = "the quick brown fox jumps over the lazy dog ";
$text = "";
for ($i = 0; $i < 2000; $i++) $text = $text . $unit;
$vow = 0;
$len = strlen($text);
for ($r = 0; $r < 5; $r++) {
    for ($i = 0; $i < $len; $i++) {
        $ch = $text[$i];
        if ($ch === 'a') $vow++;
        if ($ch === 'e') $vow++;
        if ($ch === 'o') $vow++;
    }
}
echo "strings_scan_long len=" . $len . " vow=$vow\n";
