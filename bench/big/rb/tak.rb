def tak(x, y, z)
  return tak(tak(x - 1, y, z), tak(y - 1, z, x), tak(z - 1, x, y)) if y < x
  z
end
r = 0
3.times { r = tak(24, 16, 8) }
puts "tak(24,16,8) x3 = #{r}"
