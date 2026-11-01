tak(x, y, z) = y < x ? tak(tak(x - 1, y, z), tak(y - 1, z, x), tak(z - 1, x, y)) : z
function main()
    r = 0
    for _ in 1:3
        r = tak(24, 16, 8)
    end
    println("tak(24,16,8) x3 = ", r)
end
main()
