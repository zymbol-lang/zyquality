<?php
$s = 0;
for ($i = 1; $i <= 10000000; $i++) $s = ($s + ($i * $i) % 1000) % 1000003;
echo "loop_mod = $s\n";
