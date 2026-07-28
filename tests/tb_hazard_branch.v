`timescale 1ns/1ps
// Branch/JAL hazard stress test.
// Expects mem[0]=222 (taken branch flush), mem[1]=555 (not-taken, no flush needed),
// mem[2]=777 (not-taken bne, no flush needed).
module tb_hazard_branch;
    reg clk = 0;
    reg rst = 1;

    top #(.IMEM_FILE("tests/hazard_branch.hex")) DUT (.clk(clk), .rst(rst));

    always #5 clk = ~clk;

    initial begin
        rst = 1;
        repeat (2) @(posedge clk);
        rst = 0;

        repeat (50) @(posedge clk);

        if (DUT.dmem[0] === 32'd222)
            $display("PASS: mem[0] = %0d (expected 222)", DUT.dmem[0]);
        else
            $display("FAIL: mem[0] = %0d (expected 222)", DUT.dmem[0]);

        if (DUT.dmem[1] === 32'd555)
            $display("PASS: mem[1] = %0d (expected 555)", DUT.dmem[1]);
        else
            $display("FAIL: mem[1] = %0d (expected 555)", DUT.dmem[1]);

        if (DUT.dmem[2] === 32'd777)
            $display("PASS: mem[2] = %0d (expected 777)", DUT.dmem[2]);
        else
            $display("FAIL: mem[2] = %0d (expected 777)", DUT.dmem[2]);

        $display("x3=%0d x12=%0d x15=%0d",
            DUT.CORE.RF.regs[3], DUT.CORE.RF.regs[12], DUT.CORE.RF.regs[15]);
        $finish;
    end
endmodule
