from _t import *
def positions(h, needle):
    out = []; i = h.find(needle)
    while i != -1: out.append(i); i = h.find(needle, i + len(needle))
    return out
t = now(); base_str = "the quick brown fox jumps over the lazy dog near the river bank"; total_len = 0
for i in range(0, 3000):
    result = base_str.replace(' ', "_"); total_len += len(result)
print("M1_replace_char:    len=%d" % total_len, "", el(t))
t = now(); sentence = "the cat sat on the mat near the hat by the flat"; total_len = 0
for i in range(0, 2000):
    result = sentence.replace("the", "a"); total_len += len(result)
print("M2_replace_str:     len=%d" % total_len, "", el(t))
t = now(); text = "the quick brown fox jumps over the dog on the floor of the room"; total_len = 0
for i in range(0, 2000):
    result = text.replace('o', "0", 2); total_len += len(result)
print("M3_replace_n:       len=%d" % total_len, "", el(t))
t = now(); haystack = "a man a plan a canal panama"; total_hits = 0
for i in range(0, 3000):
    p = positions(haystack, 'a'); total_hits += len(p)
print("M4_findpos_char:    hits=%d" % total_hits, "", el(t))
t = now(); corpus = "a man a plan a canal panama banana"; total_hits = 0
for i in range(0, 2000):
    p = positions(corpus, "an"); total_hits += len(p)
print("M5_findpos_str:     hits=%d" % total_hits, "", el(t))
t = now(); base = "content goes here for this item"; total_len = 0
for i in range(0, 2000):
    tagged = "[ITEM] " + base; total_len += len(tagged)
print("M6_insert_front:    len=%d" % total_len, "", el(t))
t = now(); word = "helloworld"; total_len = 0
for i in range(0, 2000):
    spaced = word[:5] + " " + word[5:]; total_len += len(spaced)
print("M7_insert_mid:      len=%d" % total_len, "", el(t))
t = now(); log_line = ">>> ERROR: connection timeout at host 192.168.1.1"; total_len = 0
for i in range(0, 3000):
    stripped = log_line[4:]; total_len += len(stripped)
print("M8_remove_prefix:   len=%d" % total_len, "", el(t))
t = now(); data = "field_name:HIDDEN:field_value"; total_len = 0
for i in range(0, 2000):
    cleaned = data[:10] + data[17:]; total_len += len(cleaned)
print("M9_remove_mid:      len=%d" % total_len, "", el(t))
t = now(); raw = "  Hello,  World!  How   are   you  today?  "; total_positions = 0
for i in range(0, 1000):
    step1 = raw.replace("  ", " "); step2 = step1.replace(",", " "); step3 = step2.replace("!", " ")
    total_positions += len(positions(step3, ' '))
print("M10_pipeline:       pos=%d" % total_positions, "", el(t))
