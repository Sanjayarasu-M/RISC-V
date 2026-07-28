`timescale 1ns/1ps
// End-to-end Phase 4 test: fpga_top (CPU + BRAM + UART) runs uart_demo.hex,
// which writes 'O' then 'K' to the UART TX register. A uart_rx instance
// decodes the serial line to confirm the bytes actually made it out
// correctly -- not just that the write happened, but that the whole
// BRAM-timing core + UART peripheral chain produces a correct serial
// bitstream.
module tb_fpga_top;
    localparam CLK_FREQ = 1_000_000; // scaled down from 50MHz for fast sim
    localparam BAUD     = 9600;      // DIV ~= 104

    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk;

    wire uart_line;

    fpga_top #(
        .CLK_FREQ_HZ(CLK_FREQ), .BAUD(BAUD),
        .IMEM_FILE("fpga/uart_demo.hex")
    ) DUT (
        .clk(clk), .rst(rst), .uart_tx_pin(uart_line)
    );

    wire [7:0] rx_data;
    wire       rx_valid;
    uart_rx #(.CLK_FREQ_HZ(CLK_FREQ), .BAUD(BAUD)) MONITOR (
        .clk(clk), .rst(rst), .rx(uart_line), .data(rx_data), .valid(rx_valid)
    );

    reg [7:0] received [0:7];
    integer   n_received = 0;

    always @(posedge clk) begin
        if (rx_valid) begin
            received[n_received] <= rx_data;
            n_received <= n_received + 1;
            $display("UART RX byte %0d: 0x%02h ('%c')", n_received, rx_data, rx_data);
        end
    end

    initial begin
        rst = 1;
        repeat (2) @(posedge clk);
        rst = 0;

        repeat (30000) @(posedge clk);

        if (n_received >= 2 && received[0] == "O" && received[1] == "K")
            $display("PASS: UART received \"OK\" correctly");
        else
            $display("FAIL: UART received %0d bytes, expected \"OK\" (got byte0=%02h byte1=%02h)",
                n_received, received[0], received[1]);

        $finish;
    end
endmodule
