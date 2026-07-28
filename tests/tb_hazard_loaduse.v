`timescale 1ns/1ps
// Load-use hazard stress test.
// Expects mem[0]=42, mem[1]=84, mem[2]=99.
module tb_hazard_loaduse;
    reg clk = 0;
    reg rst = 1;

    top #(.IMEM_FILE("tests/hazard_loaduse.hex")) DUT (.clk(clk), .rst(rst));

    always #5 clk = ~clk;

    initial begin
        rst = 1;
        repeat (2) @(posedge clk);
        rst = 0;

        repeat (40) @(posedge clk);

        if (DUT.dmem[0] === 32'd42)
            $display("PASS: mem[0] = %0d (expected 42)", DUT.dmem[0]);
        else
            $display("FAIL: mem[0] = %0d (expected 42)", DUT.dmem[0]);

        if (DUT.dmem[1] === 32'd84)
            $display("PASS: mem[1] = %0d (expected 84)", DUT.dmem[1]);
        else
            $display("FAIL: mem[1] = %0d (expected 84)", DUT.dmem[1]);

        if (DUT.dmem[2] === 32'd99)
            $display("PASS: mem[2] = %0d (expected 99)", DUT.dmem[2]);
        else
            $display("FAIL: mem[2] = %0d (expected 99)", DUT.dmem[2]);

        $display("x1=%0d x3=%0d x7=%0d x8=%0d x9=%0d",
            DUT.CORE.RF.regs[1], DUT.CORE.RF.regs[3], DUT.CORE.RF.regs[7],
            DUT.CORE.RF.regs[8], DUT.CORE.RF.regs[9]);
        $finish;
    end
endmodule
