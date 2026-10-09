from _t import *
t = now(); s = ""
for i in range(0, 8000): s = s + "x"
print("S1_heavy_concat:    len=%d" % len(s), "", el(t))
t = now(); csv = "alpha,beta,gamma,delta,epsilon,zeta,eta,theta,iota,kappa,lambda,mu,nu"; total_tokens = 0
for i in range(0, 2000): total_tokens += len(csv.split(','))
print("S2_tokenize:        total=%d" % total_tokens, "", el(t))
t = now(); text = "the quick brown fox jumps over the lazy dog near the river bank"; slice_total = 0
for i in range(0, 4000):
    start = i % 53 + 1; end = start + 9
    sl = text[start - 1:end]; slice_total += len(sl)
print("S3_sliding_slices:  chars=%d" % slice_total, "", el(t))
t = now(); corpus = "the quick brown fox jumps over the lazy dog"; vowels = consonants = 0
for _ in range(0, 400):
    for ch in corpus:
        is_vowel = ch == 'a' or ch == 'e' or ch == 'i' or ch == 'o' or ch == 'u'
        is_space = ch == ' '
        if is_vowel: vowels += 1
        if (not is_vowel) and (not is_space): consonants += 1
print("S4_char_freq:       vowels=%d consonants=%d" % (vowels, consonants), "", el(t))
t = now(); haystack = "artificial intelligence natural language processing machine learning neural network deep"
patterns = ["intel", "lang", "learn", "neural", "deep"]; hits = 0
for i in range(1, 3001):
    p = patterns[(i - 1) % 5]
    if p in haystack: hits += 1
print("S5_multi_search:    hits=%d" % hits, "", el(t))
t = now(); template_total = 0
for i in range(0, 4000):
    sq = i * i; line = "row:" + str(i) + " sq:" + str(sq) + " tag:item-" + str(i) + "-end"
    template_total += len(line)
print("S6_template_build:  chars=%d" % template_total, "", el(t))
t = now(); sentence = "the quick brown fox jumps over the lazy dog"; word_chars = long_words = 0
for _ in range(0, 1000):
    words = sentence.split(' ')
    for w in words:
        wlen = len(w); word_chars += wlen
        if wlen > 4: long_words += 1
print("S7_word_analysis:   total=%d long=%d" % (word_chars, long_words), "", el(t))
t = now(); data = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"; chunk_total = 0
for i in range(0, 5000):
    pos = (i * 7) % 57 + 1; pend = pos + 4
    chunk = data[pos - 1:pend]; chunk_total += len(chunk)
print("S8_chunk_extract:   total=%d" % chunk_total, "", el(t))
t = now(); wlist = ["one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten"]; join_total = 0
for _ in range(0, 400):
    joined = ""
    for j in range(1, 11):
        if j > 1: joined = joined + ","
        joined = joined + wlist[j - 1]
    join_total += len(joined)
print("S9_join_sim:        total=%d" % join_total, "", el(t))
t = now(); fmt_total = 0
for i in range(0, 6000):
    diff = i - 3000; score = i * 37 % 1000
    record = "id=" + str(i) + " diff=" + str(diff) + " score=" + str(score)
    fmt_total += len(record)
print("S10_num_format:     chars=%d" % fmt_total, "", el(t))
