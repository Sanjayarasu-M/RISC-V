# Basic QDOT8 correctness test (single instruction, no hazards).
#   A = x4:x5  = [1,2,3,4] : [5,6,7,8]
#   B = x10:x11 = [1,1,1,1] : [2,2,2,2]
#   dot = (1*1+2*1+3*1+4*1) + (5*2+6*2+7*2+8*2) = 10 + 52 = 62
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
qdot8 x6, x4, x10        # x6 = 0 + 62 = 62
sw   x6, 0(x0)           # mem[0] = 62 (expected)
jal  x0, 0
