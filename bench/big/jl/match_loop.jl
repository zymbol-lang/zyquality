function classify(x)
    0 <= x <= 9 && return 1
    10 <= x <= 49 && return 2
    50 <= x <= 99 && return 3
    return 4
end
function main()
    acc = 0
    for i in 1:3000000
        acc += classify(i % 150)
    end
    println("match_loop ", acc)
end
main()
