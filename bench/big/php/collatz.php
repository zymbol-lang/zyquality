<?php
$best = 0; $bestn = 0;
for ($n = 1; $n <= 60000; $n++) {
    $x = $n; $steps = 0;
    while ($x != 1) {
        if ($x % 2 == 0) $x = intdiv($x, 2);
        else $x = 3 * $x + 1;
        $steps++;
    }
    if ($steps > $best) { $best = $steps; $bestn = $n; }
}
echo "collatz $bestn $best\n";
