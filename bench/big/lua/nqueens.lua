local function safe(cols, c)
  local n = #cols
  local r, ok = 1, true
  while r <= n do
    local d = cols[r] - c
    if d == 0 then ok = false end
    if d == (n + 1 - r) then ok = false end
    if d == (r - n - 1) then ok = false end
    r = r + 1
  end
  return ok
end
local function place(n, cols)
  if #cols == n then return 1 end
  local total, c = 0, 1
  while c <= n do
    if safe(cols, c) then
      local next = {}
      for i = 1, #cols do next[i] = cols[i] end
      next[#cols + 1] = c
      total = total + place(n, next)
    end
    c = c + 1
  end
  return total
end
print("nqueens(10) = " .. place(10, {}))
