primes = []
count = 0
(2..300000).each do |n|
  isp = true
  k = 1
  while k <= count
    p = primes[k - 1]
    break if p * p > n
    if n % p == 0
      isp = false
      break
    end
    k += 1
  end
  if isp
    primes << n
    count += 1
  end
end
puts "primes #{count} #{primes[count - 1]}"
