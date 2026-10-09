import time
def now(): return time.perf_counter()
def el(t): return "(%.3fs)" % (time.perf_counter() - t)
