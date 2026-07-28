# QDOT8 register-pair (rs1_hi/rs2_hi) hazard test: specifically exercises
# the NEW hazard/forwarding paths added for the "+1" partner registers,
# which the plain hazard_qdot8.s test doesn't touch (there, x5/x11 are set
# up long before they're used).
#
#   A = x4:x5  = [1,2,3,4] : [5,6,7,8]
#   B = x10:x11 = [1,1,1,1] : [?,?,?,?]
#
# Part 1: x5 (=x4+1, A's hi half) is produced by a LOAD, and the very next
#   instruction is a QDOT8 that reads x5 as rs1_hi. Load results aren't
#   ready until end-of-MEM, so this must trigger hazard_stall's
#   uses_rs1_hi_d path (one bubble), then satisfy rs1_hi from the
#   MEM/WB-stage forward (fwd_a_hi).
#
# Part 2: x11 (=x10+1, B's hi half) is produced by an ALU op (lui/ori,
#   result ready at end of EX), and the very next instruction is a QDOT8
#   that reads x11 as rs2_hi -- no stall needed, but must be satisfied by
#   the EX/MEM-stage forward (fwd_b_hi).
#
lui  x4,  0x04030
ori  x4,  x4,  0x201     # x4  = 0x04030201 -> [1,2,3,4]
lui  x10, 0x01010
ori  x10, x10, 0x101     # x10 = 0x01010101 -> [1,1,1,1]
lui  x11, 0x02020
ori  x11, x11, 0x202     # x11 = 0x02020202 -> [2,2,2,2] (baseline, avoid X)
addi x6, x0, 0

# --- build 0x08070605 in scratch reg x20, store it, then load it back
# into x5 so x5's producer is a LOAD (not an ALU op) ---
lui  x20, 0x08070
ori  x20, x20, 0x605     # x20 = 0x08070605 -> [5,6,7,8]
sw   x20, 0(x0)          # mem[0] = 0x08070605
addi x0, x0, 0           # nop: let the store settle before reading it back
addi x0, x0, 0           # nop

lw   x5, 0(x0)           # x5 = 0x08070605  <- LOAD producer of A's hi half
qdot8 x6, x4, x10        # immediately uses rs1_hi=x5 -> stall + MEM/WB forward
                          # dot = (1+2+3+4) + (5*2+6*2+7*2+8*2) = 10+52 = 62
                          # x6 = 0 + 62 = 62
sw   x6, 8(x0)           # mem[2] = 62 (expected, part 1 checkpoint)

lui  x11, 0x03030
ori  x11, x11, 0x303     # x11 = 0x03030303 -> [3,3,3,3]  <- ALU producer of B's hi half
qdot8 x6, x4, x10        # immediately uses rs2_hi=x11 -> EX/MEM forward, no stall
                          # dot = (1+2+3+4) + (5*3+6*3+7*3+8*3) = 10+78 = 88
                          # x6 = 62 + 88 = 150

sw   x6, 4(x0)           # mem[1] = 150 (expected)
jal  x0, 0
