# Branch hazard stress test: covers a taken branch (needs flush of the
# two wrong-path instructions fetched after it), a not-taken branch
# (must NOT flush, just fall through), and a taken backward-ish branch,
# plus a JAL (resolved in ID, 1-instruction flush).
#
addi x1, x0, 5
addi x2, x0, 5
beq  x1, x2, TAKEN1     # 5==5 -> taken, must skip the next instruction
addi x3, x0, 111        # SKIPPED if branch logic is correct
TAKEN1:
addi x3, x0, 222        # x3 = 222 (expected)
addi x4, x0, 1
addi x11, x0, 2
beq  x4, x11, WRONG      # 1!=2 -> NOT taken, must fall through
addi x12, x0, 555        # executes (branch not taken)
jal  x0, SKIPWRONG
WRONG:
addi x12, x0, 999
SKIPWRONG:
addi x13, x0, 1
addi x14, x0, 1
bne  x13, x14, WRONG2     # 1==1 -> NOT taken (bne false), fall through
addi x15, x0, 777         # executes
jal  x0, DONE
WRONG2:
addi x15, x0, 888
DONE:
sw   x3, 0(x0)            # mem[0] = 222
sw   x12, 4(x0)           # mem[1] = 555
sw   x15, 8(x0)           # mem[2] = 777
jal  x0, 0
