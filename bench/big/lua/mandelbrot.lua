local w, h, maxit = 250, 250, 100
local inside = 0
for py = 0, h - 1 do
  for px = 0, w - 1 do
    local cr = (3.0 * px) / w - 2.0
    local ci = (2.0 * py) / h - 1.0
    local zr, zi, it = 0.0, 0.0, 0
    while it < maxit do
      local t = zr * zr - zi * zi + cr
      zi = 2.0 * zr * zi + ci
      zr = t
      if zr * zr + zi * zi > 4.0 then break end
      it = it + 1
    end
    if it == maxit then inside = inside + 1 end
  end
end
print("mandelbrot inside=" .. inside)
