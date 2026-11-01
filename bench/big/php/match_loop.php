<?php
function classify($x) {
    if (0 <= $x && $x <= 9) return 1;
    if (10 <= $x && $x <= 49) return 2;
    if (50 <= $x && $x <= 99) return 3;
    return 4;
}
$acc = 0;
for ($i = 1; $i <= 3000000; $i++) $acc += classify($i % 150);
echo "match_loop $acc\n";
