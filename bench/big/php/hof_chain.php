<?php
$nums = range(1, 100000);
$total = 0;
for ($r = 0; $r < 25; $r++) {
    $sq = array_map(fn($x) => $x * $x, $nums);
    $ev = array_filter($sq, fn($x) => $x % 3 == 0);
    $s = array_reduce($ev, fn($acc, $x) => $acc + $x, 0);
    $total += $s;
}
echo "hof_chain total = $total\n";
