unit = "the quick brown fox jumps over the lazy dog "
text = ""
for _ in range(100):
    text = text + unit
vow = 0
for _ in range(200):
    for ch in text:
        if ch == 'a':
            vow += 1
        if ch == 'e':
            vow += 1
        if ch == 'o':
            vow += 1
print("strings_scan_short len=" + str(len(text)) + " vow=" + str(vow))
