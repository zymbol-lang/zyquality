const unit = "the quick brown fox jumps over the lazy dog ";
let text = "";
for (let i = 0; i < 2000; i++) text = text + unit;
let vow = 0;
for (let r = 0; r < 5; r++) {
  for (const ch of text) {
    if (ch === 'a') vow++;
    if (ch === 'e') vow++;
    if (ch === 'o') vow++;
  }
}
console.log("strings_scan_long len=" + text.length + " vow=" + vow);
