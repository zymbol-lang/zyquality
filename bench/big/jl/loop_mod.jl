function main()
    s = 0
    for i in 1:10000000
        s = (s + (i * i) % 1000) % 1000003
    end
    println("loop_mod = ", s)
end
main()
