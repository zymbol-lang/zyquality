n = 300000
v = []
x = 12345
n.times do
  x = (x * 1103 + 12345) % 1000003
  v << x
end
r = v.sort { |p, q| p < q ? -1 : (p > q ? 1 : 0) }
puts "sort_cmp_300k #{r[0]} #{r[n / 2 - 1]} #{r[n - 1]}"
