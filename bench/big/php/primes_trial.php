<?php
$primes = []; $count = 0;
for ($n = 2; $n <= 300000; $n++) {
    $isp = true; $k = 1;
    while ($k <= $count) {
        $p = $primes[$k - 1];
        if ($p * $p > $n) break;
        if ($n % $p == 0) { $isp = false; break; }
        $k++;
    }
    if ($isp) { $primes[] = $n; $count++; }
}
echo "primes $count " . $primes[$count - 1] . "\n";
