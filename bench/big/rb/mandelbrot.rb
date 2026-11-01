w = 250
h = 250
maxit = 100
inside = 0
(0...h).each do |py|
  (0...w).each do |px|
    cr = (3.0 * px) / w - 2.0
    ci = (2.0 * py) / h - 1.0
    zr = 0.0
    zi = 0.0
    it = 0
    while it < maxit
      t = zr * zr - zi * zi + cr
      zi = 2.0 * zr * zi + ci
      zr = t
      break if zr * zr + zi * zi > 4.0
      it = it + 1
    end
    inside += 1 if it == maxit
  end
end
puts "mandelbrot inside=#{inside}"
