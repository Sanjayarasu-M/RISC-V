# Back-to-back dependent QDOT8 stress test (mirrors tests/hazard_qdot4.s).
# Each QDOT8 accumulates into x6, and the very next QDOT8 immediately
# reads x6 back out as its accumulate source (rd-as-source hazard).
# QDOT8's result is only ready after MEM (like a load/QDOT4), so this
# exercises the load-use-style stall and rd_src forwarding for QDOT8.
#
#   A = x4:x5  = [1,2,3,4] : [5,6,7,8]
#   B = x10:x11 = [1,1,1,1] : [2,2,2,2]
#   dot = 10 + 52 = 62 each time
#
lui  x4,  0x04030
ori  x4,  x4,  0x201     # x4  = 0x04030201 -> [1,2,3,4]
lui  x5,  0x08070
ori  x5,  x5,  0x605     # x5  = 0x08070605 -> [5,6,7,8]
lui  x10, 0x01010
ori  x10, x10, 0x101     # x10 = 0x01010101 -> [1,1,1,1]
lui  x11, 0x02020
ori  x11, x11, 0x202     # x11 = 0x02020202 -> [2,2,2,2]
addi x6, x0, 0
qdot8 x6, x4, x10        # x6 = 0   + 62 = 62
qdot8 x6, x4, x10        # x6 = 62  + 62 = 124  <- immediately reads x6 back
qdot8 x6, x4, x10        # x6 = 124 + 62 = 186  <- again
qdot8 x6, x4, x10        # x6 = 186 + 62 = 248  <- again
sw   x6, 0(x0)           # mem[0] = 248 (expected)
jal  x0, 0
