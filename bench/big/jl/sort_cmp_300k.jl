function main()
    n = 300000
    v = Int[]
    x = 12345
    for _ in 1:n
        x = (x * 1103 + 12345) % 1000003
        push!(v, x)
    end
    r = sort(v, lt = (p, q) -> p < q)
    println("sort_cmp_300k ", r[1], " ", r[n ÷ 2], " ", r[n])
end
main()
