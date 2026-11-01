n = 150
a = []
b = []
(0...n).each do |i|
  (0...n).each do |j|
    a << (i * j) % 10
    b << (i + j) % 7
  end
end
chk = 0
(0...n).each do |i|
  (0...n).each do |j|
    s = 0
    (0...n).each { |k| s = s + a[i * n + k] * b[k * n + j] }
    chk = (chk + s * (i + j + 1)) % 1000003
  end
end
puts "matmul chk = #{chk}"
