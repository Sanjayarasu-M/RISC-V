// crt0.S -- minimal bare-metal startup for the QDOT4 RISC-V core.
// No OS, no syscalls, no libc: set up sp, zero .bss, call main, then halt.
.section .text.start
.global _start
_start:
    lui  sp, %hi(_stack_top)
    addi sp, sp, %lo(_stack_top)

    lui  t0, %hi(_bss_start)
    addi t0, t0, %lo(_bss_start)
    lui  t1, %hi(_bss_end)
    addi t1, t1, %lo(_bss_end)
bss_zero_loop:
    bge  t0, t1, bss_zero_done
    sw   x0, 0(t0)
    addi t0, t0, 4
    jal  x0, bss_zero_loop
bss_zero_done:
    jal  ra, main

halt:
    jal  x0, halt
