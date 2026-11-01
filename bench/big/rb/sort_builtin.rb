n = 600000
v = []
x = 12345
n.times do
  x = (x * 1103 + 12345) % 1000003
  v << x
end
r = v.sort
puts "sort_builtin #{r[0]} #{r[299999]} #{r[n - 1]}"
