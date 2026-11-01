local n = 150
local a, b = {}, {}
for i = 0, n - 1 do
  for j = 0, n - 1 do
    a[#a + 1] = (i * j) % 10
    b[#b + 1] = (i + j) % 7
  end
end
local chk = 0
for i = 0, n - 1 do
  for j = 0, n - 1 do
    local s = 0
    for k = 0, n - 1 do s = s + a[i * n + k + 1] * b[k * n + j + 1] end
    chk = (chk + s * (i + j + 1)) % 1000003
  end
end
print("matmul chk = " .. chk)
