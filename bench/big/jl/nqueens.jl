function safe(cols, c)
    n = length(cols)
    r = 1
    ok = true
    while r <= n
        d = cols[r] - c
        if d == 0
            ok = false
        end
        if d == (n + 1 - r)
            ok = false
        end
        if d == (r - n - 1)
            ok = false
        end
        r += 1
    end
    return ok
end
function place(n, cols)
    length(cols) == n && return 1
    total = 0
    c = 1
    while c <= n
        if safe(cols, c)
            total += place(n, vcat(cols, c))
        end
        c += 1
    end
    return total
end
println("nqueens(10) = ", place(10, Int[]))
