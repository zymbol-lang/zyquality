function main()
    m = 20000
    v = zeros(Int, m)
    for i in 1:3000
        v[i] = i
    end
    println("array_update ", v[3000], " ", length(v))
end
main()
