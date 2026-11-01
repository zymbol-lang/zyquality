local unit = "the quick brown fox jumps over the lazy dog "
local text = ""
for _ = 1, 100 do text = text .. unit end
local vow = 0
local len = #text
for _ = 1, 200 do
  for i = 1, len do
    local ch = text:sub(i, i)
    if ch == 'a' then vow = vow + 1 end
    if ch == 'e' then vow = vow + 1 end
    if ch == 'o' then vow = vow + 1 end
  end
end
print("strings_scan_short len=" .. len .. " vow=" .. vow)
