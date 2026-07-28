# uart_demo.s -- writes "OK" to the UART_TX_ADDR register (0x7F0), with a
# software delay loop between bytes since this UART peripheral has no
# ready/backpressure readback to the CPU (see fpga_top.v).
addi x5, x0, 0x7F0        # x5 = UART_TX_ADDR
addi x6, x0, 79           # 'O' = 0x4F = 79
sw   x6, 0(x5)
addi x7, x0, 2000
DELAY1:
addi x7, x7, -1
bne  x7, x0, DELAY1
addi x6, x0, 75           # 'K' = 0x4B = 75
sw   x6, 0(x5)
addi x7, x0, 2000
DELAY2:
addi x7, x7, -1
bne  x7, x0, DELAY2
jal  x0, 0
