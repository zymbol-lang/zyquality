nums = (1..100000).to_a
total = 0
25.times do
  sq = nums.map { |x| x * x }
  ev = sq.select { |x| x % 3 == 0 }
  s = ev.reduce(0) { |acc, x| acc + x }
  total += s
end
puts "hof_chain total = #{total}"
