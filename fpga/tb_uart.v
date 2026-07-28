`timescale 1ns/1ps
// Self-checking loopback test: uart_tx -> wire -> uart_rx, several bytes.
// Uses a small clock/baud ratio to keep simulation time short.
module tb_uart;
    localparam CLK_FREQ = 50_000_000;
    localparam BAUD     = 115200; // DIV ~= 434, matches the real target parameters

    reg clk = 0;
    reg rst = 1;
    always #5 clk = ~clk; // 100MHz-scaled-down for sim convenience

    reg  [7:0] tx_data;
    reg        tx_valid;
    wire       tx_ready;
    wire       tx_line;

    wire [7:0] rx_data;
    wire       rx_valid;

    uart_tx #(.CLK_FREQ_HZ(CLK_FREQ), .BAUD(BAUD)) TX (
        .clk(clk), .rst(rst), .data(tx_data), .valid(tx_valid), .ready(tx_ready), .tx(tx_line)
    );
    uart_rx #(.CLK_FREQ_HZ(CLK_FREQ), .BAUD(BAUD)) RX (
        .clk(clk), .rst(rst), .rx(tx_line), .data(rx_data), .valid(rx_valid)
    );

    integer errors = 0;

    task send_and_check(input [7:0] b);
        begin
            @(posedge clk);
            while (!tx_ready) @(posedge clk);
            tx_data  <= b;
            tx_valid <= 1'b1;
            @(posedge clk);
            tx_valid <= 1'b0;

            // wait for rx to capture it
            wait (rx_valid === 1'b1);
            if (rx_data !== b) begin
                $display("FAIL: sent 0x%02h, received 0x%02h", b, rx_data);
                errors = errors + 1;
            end else begin
                $display("PASS: byte 0x%02h round-tripped correctly", b);
            end
            @(posedge clk); // let valid pulse clear
        end
    endtask

    initial begin
        tx_valid = 0;
        tx_data  = 0;
        rst = 1;
        repeat (3) @(posedge clk);
        rst = 0;
        repeat (2) @(posedge clk);

        send_and_check(8'h55);
        send_and_check(8'hA5);
        send_and_check(8'h00);
        send_and_check(8'hFF);
        send_and_check(8'h3C); // '<'

        if (errors == 0)
            $display("PASS: all UART loopback bytes matched");
        else
            $display("FAIL: %0d UART loopback mismatches", errors);

        $finish;
    end
endmodule
