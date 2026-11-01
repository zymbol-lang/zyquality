m = 20000
v = Array.new(m, 0)
(1..3000).each { |i| v[i - 1] = i }
puts "array_update #{v[2999]} #{v.length}"
