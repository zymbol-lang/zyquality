const unit = "the quick brown fox jumps over the lazy dog ";
let text = "";
for (let i = 0; i < 100; i++) text = text + unit;
let vow = 0;
for (let r = 0; r < 200; r++) {
  for (const ch of text) {
    if (ch === 'a') vow++;
    if (ch === 'e') vow++;
    if (ch === 'o') vow++;
  }
}
console.log("strings_scan_short len=" + text.length + " vow=" + vow);
