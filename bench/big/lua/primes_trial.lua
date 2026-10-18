local primes, count = {}, 0
for n = 2, 300000 do
  local isp, k = true, 1
  while k <= count do
    local p = primes[k]
    if p * p > n then break end
    if n % p == 0 then isp = false; break end
    k = k + 1
  end
  if isp then count = count + 1; primes[count] = n end
end
print("primes " .. count .. " " .. primes[count])
