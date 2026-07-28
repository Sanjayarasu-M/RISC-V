`timescale 1ns/1ps
// Back-to-back dependent QDOT4 hazard stress test.
// Expects mem[0] == 40 (four chained accumulates of 10 each).
module tb_hazard_qdot4;
    reg clk = 0;
    reg rst = 1;

    top #(.IMEM_FILE("tests/hazard_qdot4.hex")) DUT (.clk(clk), .rst(rst));

    always #5 clk = ~clk;

    initial begin
        rst = 1;
        repeat (2) @(posedge clk);
        rst = 0;

        repeat (40) @(posedge clk);

        if (DUT.dmem[0] === 32'd40) begin
            $display("PASS: hazard_qdot4 result = %0d (expected 40)", DUT.dmem[0]);
        end else begin
            $display("FAIL: hazard_qdot4 result = %0d (expected 40)", DUT.dmem[0]);
        end
        $display("x6=%0d", DUT.CORE.RF.regs[6]);
        $finish;
    end
endmodule
