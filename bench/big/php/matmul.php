<?php
$n = 150;
$a = []; $b = [];
for ($i = 0; $i < $n; $i++)
    for ($j = 0; $j < $n; $j++) { $a[] = ($i * $j) % 10; $b[] = ($i + $j) % 7; }
$chk = 0;
for ($i = 0; $i < $n; $i++) {
    for ($j = 0; $j < $n; $j++) {
        $s = 0;
        for ($k = 0; $k < $n; $k++) $s = $s + $a[$i * $n + $k] * $b[$k * $n + $j];
        $chk = ($chk + $s * ($i + $j + 1)) % 1000003;
    }
}
echo "matmul chk = $chk\n";
