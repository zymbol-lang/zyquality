function main()
    n = 600000
    v = Int[]
    x = 12345
    for _ in 1:n
        x = (x * 1103 + 12345) % 1000003
        push!(v, x)
    end
    r = sort(v)
    println("sort_builtin ", r[1], " ", r[300000], " ", r[n])
end
main()
