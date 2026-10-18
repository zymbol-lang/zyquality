def safe(cols, c)
  n = cols.length
  r = 1
  ok = true
  while r <= n
    d = cols[r - 1] - c
    ok = false if d == 0
    ok = false if d == (n + 1 - r)
    ok = false if d == (r - n - 1)
    r += 1
  end
  ok
end
def place(n, cols)
  return 1 if cols.length == n
  total = 0
  c = 1
  while c <= n
    total += place(n, cols + [c]) if safe(cols, c)
    c += 1
  end
  total
end
puts "nqueens(10) = #{place(10, [])}"
