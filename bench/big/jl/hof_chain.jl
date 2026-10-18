function main()
    nums = collect(1:100000)
    total = 0
    for _ in 1:25
        sq = map(x -> x * x, nums)
        ev = filter(x -> x % 3 == 0, sq)
        s = reduce((acc, x) -> acc + x, ev; init = 0)
        total += s
    end
    println("hof_chain total = ", total)
end
main()
