local function map(f, t) local r = {} for i = 1, #t do r[i] = f(t[i]) end return r end
local function filter(f, t) local r = {} for i = 1, #t do if f(t[i]) then r[#r + 1] = t[i] end end return r end
local function reduce(f, init, t) local acc = init for i = 1, #t do acc = f(acc, t[i]) end return acc end
local nums = {}
for i = 1, 100000 do nums[i] = i end
local total = 0
for _ = 1, 25 do
  local sq = map(function(x) return x * x end, nums)
  local ev = filter(function(x) return x % 3 == 0 end, sq)
  local s = reduce(function(acc, x) return acc + x end, 0, ev)
  total = total + s
end
print("hof_chain total = " .. total)
