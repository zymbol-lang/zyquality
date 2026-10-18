def classify(x)
  return 1 if 0 <= x && x <= 9
  return 2 if 10 <= x && x <= 49
  return 3 if 50 <= x && x <= 99
  4
end
acc = 0
(1..3000000).each { |i| acc += classify(i % 150) }
puts "match_loop #{acc}"
