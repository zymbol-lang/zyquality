<?php
$unit = "the quick brown fox jumps over the lazy dog ";
$text = "";
for ($i = 0; $i < 100; $i++) $text = $text . $unit;
$vow = 0;
$len = strlen($text);
for ($r = 0; $r < 200; $r++) {
    for ($i = 0; $i < $len; $i++) {
        $ch = $text[$i];
        if ($ch === 'a') $vow++;
        if ($ch === 'e') $vow++;
        if ($ch === 'o') $vow++;
    }
}
echo "strings_scan_short len=" . $len . " vow=$vow\n";
