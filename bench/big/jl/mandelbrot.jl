function main()
    w = 250
    h = 250
    maxit = 100
    inside = 0
    for py in 0:h-1
        for px in 0:w-1
            cr = (3.0 * px) / w - 2.0
            ci = (2.0 * py) / h - 1.0
            zr = 0.0
            zi = 0.0
            it = 0
            while it < maxit
                t = zr * zr - zi * zi + cr
                zi = 2.0 * zr * zi + ci
                zr = t
                if zr * zr + zi * zi > 4.0
                    break
                end
                it = it + 1
            end
            if it == maxit
                inside += 1
            end
        end
    end
    println("mandelbrot inside=", inside)
end
main()
