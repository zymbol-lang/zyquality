function main()
    n = 150
    a = Int[]
    b = Int[]
    for i in 0:n-1, j in 0:n-1
        push!(a, (i * j) % 10)
        push!(b, (i + j) % 7)
    end
    chk = 0
    for i in 0:n-1
        for j in 0:n-1
            s = 0
            for k in 0:n-1
                s = s + a[i * n + k + 1] * b[k * n + j + 1]
            end
            chk = (chk + s * (i + j + 1)) % 1000003
        end
    end
    println("matmul chk = ", chk)
end
main()
