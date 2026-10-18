function main()
    primes = Int[]
    count = 0
    for n in 2:300000
        isp = true
        k = 1
        while k <= count
            p = primes[k]
            if p * p > n
                break
            end
            if n % p == 0
                isp = false
                break
            end
            k += 1
        end
        if isp
            push!(primes, n)
            count += 1
        end
    end
    println("primes ", count, " ", primes[count])
end
main()
