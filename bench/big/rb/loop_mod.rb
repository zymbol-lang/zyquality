s = 0
(1..10000000).each do |i|
  s = (s + (i * i) % 1000) % 1000003
end
puts "loop_mod = #{s}"
