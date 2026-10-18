function main()
    unit = "the quick brown fox jumps over the lazy dog "
    text = ""
    for _ in 1:100
        text = text * unit
    end
    vow = 0
    for _ in 1:200
        for ch in text
            if ch == 'a'
                vow += 1
            end
            if ch == 'e'
                vow += 1
            end
            if ch == 'o'
                vow += 1
            end
        end
    end
    println("strings_scan_short len=", length(text), " vow=", vow)
end
main()
