# Load-use hazard stress test: the instruction right after a load
# immediately consumes the loaded register (classic 1-bubble stall case).
#
addi x2, x0, 0        # base address = 0
addi x5, x0, 42       # value to store
sw   x5, 0(x2)        # mem[0] = 42
lw   x1, 0(x2)        # x1 = mem[0] = 42            <- load
add  x3, x1, x1       # x3 = x1 + x1 = 84           <- immediate load-use
sw   x3, 4(x2)        # mem[1] = 84 (expected)
lw   x7, 0(x2)        # x7 = 42                     <- second load
sub  x8, x7, x1       # x8 = 42 - 42 = 0            <- immediate load-use again
addi x9, x8, 99       # x9 = 99                     <- back-to-back dependency on ALU result too
sw   x9, 8(x2)        # mem[2] = 99 (expected)
jal  x0, 0
