# Back-to-back dependent QDOT4 stress test.
# Each QDOT4 accumulates into x6, and the very next QDOT4 immediately
# reads x6 back out as its accumulate source (rd-as-source hazard).
# QDOT4 result is only ready after the MEM stage (like a load), so this
# exercises both the load-use-style stall and rd_src forwarding.
#
#   x4 = 0x04030201 -> int8 lanes [1,2,3,4]
#   x5 = 0x01010101 -> int8 lanes [1,1,1,1]
#   dot = 1*1+2*1+3*1+4*1 = 10 each time
#
lui  x4, 0x04030
ori  x4, x4, 0x201
lui  x5, 0x01010
ori  x5, x5, 0x101
addi x6, x0, 0
qdot4 x6, x4, x5      # x6 = 0  + 10 = 10
qdot4 x6, x4, x5      # x6 = 10 + 10 = 20   <- immediately reads x6 (back-to-back dependency)
qdot4 x6, x4, x5      # x6 = 20 + 10 = 30   <- again
qdot4 x6, x4, x5      # x6 = 30 + 10 = 40   <- again
sw   x6, 0(x0)        # mem[0] = 40 (expected)
jal  x0, 0
