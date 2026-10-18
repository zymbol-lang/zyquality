best = 0
bestn = 0
(1..60000).each do |n|
  x = n
  steps = 0
  while x != 1
    if x % 2 == 0
      x = x / 2
    else
      x = 3 * x + 1
    end
    steps += 1
  end
  if steps > best
    best = steps
    bestn = n
  end
end
puts "collatz #{bestn} #{best}"
