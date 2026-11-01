unit = "the quick brown fox jumps over the lazy dog "
text = ""
for _ in range(2000):
    text = text + unit
vow = 0
for _ in range(5):
    for ch in text:
        if ch == 'a':
            vow += 1
        if ch == 'e':
            vow += 1
        if ch == 'o':
            vow += 1
print("strings_scan_long len=" + str(len(text)) + " vow=" + str(vow))
