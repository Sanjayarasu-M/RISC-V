`timescale 1ns/1ps
// Basic QDOT8 correctness test. Expects mem[0] == 62.
module tb_qdot8_basic;
    reg clk = 0;
    reg rst = 1;

    top #(.IMEM_FILE("tests/qdot8_basic.hex")) DUT (.clk(clk), .rst(rst));

    always #5 clk = ~clk;

    initial begin
        rst = 1;
        repeat (2) @(posedge clk);
        rst = 0;

        repeat (30) @(posedge clk);

        if (DUT.dmem[0] === 32'd62) begin
            $display("PASS: qdot8_basic result = %0d (expected 62)", DUT.dmem[0]);
        end else begin
            $display("FAIL: qdot8_basic result = %0d (expected 62)", DUT.dmem[0]);
        end
        $finish;
    end
endmodule
