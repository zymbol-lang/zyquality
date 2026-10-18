unit = "the quick brown fox jumps over the lazy dog "
text = ""
2000.times { text = text + unit }
vow = 0
5.times do
  text.each_char do |ch|
    vow += 1 if ch == 'a'
    vow += 1 if ch == 'e'
    vow += 1 if ch == 'o'
  end
end
puts "strings_scan_long len=#{text.length} vow=#{vow}"
