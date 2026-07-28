# Reference assembly for program.hex (hand-assembled RV32I + custom QDOT4)
# Computes a 4-lane signed int8 dot product accumulate and stores the result.
#
#   addi x1, x0, 5          # x1 = 5           (unused, just exercises ADDI)
#   addi x2, x0, 10         # x2 = 10
#   add  x3, x1, x2         # x3 = 15          (exercises R-type ADD)
#   lui  x4, 0x04030        # x4 = 0x04030000
#   ori  x4, x4, 0x201      # x4 = 0x04030201  -> int8 lanes [1,2,3,4]
#   lui  x5, 0x01010        # x5 = 0x01010000
#   ori  x5, x5, 0x101      # x5 = 0x01010101  -> int8 lanes [1,1,1,1]
#   addi x6, x0, 0          # x6 = 0           (accumulator, must start at 0)
#   qdot4 x6, x4, x5        # x6 = x6 + (1*1 + 2*1 + 3*1 + 4*1) = 10   <-- custom instruction
#   sw   x6, 0(x0)          # mem[0] = 10      (write result out for verification)
#   jal  x0, 0               # halt (infinite loop on self)
#
# QDOT4 encoding used above (custom-0 opcode 0x0B, funct3=0, funct7=0):
#   qdot4 rd, rs1, rs2  ==  .insn r 0x0B, 0, 0, rd, rs1, rs2   (usable directly in C via inline asm)
