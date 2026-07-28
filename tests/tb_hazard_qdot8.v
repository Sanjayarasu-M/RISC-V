`timescale 1ns/1ps
// Back-to-back dependent QDOT8 hazard stress test.
// Expects mem[0] == 248 (four chained accumulates of 62 each).
module tb_hazard_qdot8;
    reg clk = 0;
    reg rst = 1;

    top #(.IMEM_FILE("tests/hazard_qdot8.hex")) DUT (.clk(clk), .rst(rst));

    always #5 clk = ~clk;

    initial begin
        rst = 1;
        repeat (2) @(posedge clk);
        rst = 0;

        repeat (40) @(posedge clk);

        if (DUT.dmem[0] === 32'd248) begin
            $display("PASS: hazard_qdot8 result = %0d (expected 248)", DUT.dmem[0]);
        end else begin
            $display("FAIL: hazard_qdot8 result = %0d (expected 248)", DUT.dmem[0]);
        end
        $display("x6=%0d", DUT.CORE.RF.regs[6]);
        $finish;
    end
endmodule
