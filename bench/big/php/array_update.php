<?php
$m = 20000;
$v = array_fill(0, $m, 0);
for ($i = 1; $i <= 3000; $i++) $v[$i - 1] = $i;
echo "array_update " . $v[2999] . " " . count($v) . "\n";
