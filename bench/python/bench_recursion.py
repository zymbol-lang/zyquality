import sys; sys.setrecursionlimit(20000)
from _t import *
def fib(n): return n if n <= 1 else fib(n-1) + fib(n-2)
def fact(n): return 1 if n <= 1 else n * fact(n-1)
def pw(b, e): return 1 if e == 0 else b * pw(b, e-1)
def ack(m, n):
    if m == 0: return n + 1
    if n == 0: return ack(m-1, 1)
    return ack(m-1, ack(m, n-1))
def sum_down(n, acc): return acc if n == 0 else sum_down(n-1, acc+n)
t = now(); r = fib(30);        print("fib(30) =", r, "", el(t))
t = now(); r = fact(18);       print("fact(18) =", r, "", el(t))
t = now(); r = pw(2, 20);      print("pow(2,20) =", r, "", el(t))
t = now(); r = ack(3, 6);      print("ackermann(3,6) =", r, "", el(t))
t = now(); r = sum_down(1000, 0); print("sum_down(1000) =", r, "", el(t))
