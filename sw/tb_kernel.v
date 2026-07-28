`timescale 1ns/1ps
// Runs the real GCC-compiled QDOT4 kernel (sw/kernel.c) on the pipelined
// core. Checks _result_ok (mem word 512, addr 0x0800) and _result_val
// (mem word 513, addr 0x0804) as defined in sw/link.ld.
module tb_kernel;
    reg clk = 0;
    reg rst = 1;

    top #(.IMEM_FILE("sw/kernel.hex"), .DMEM_FILE("sw/kernel_data.hex")) DUT (.clk(clk), .rst(rst));

    always #5 clk = ~clk;

    initial begin
        rst = 1;
        repeat (2) @(posedge clk);
        rst = 0;

        repeat (3000) @(posedge clk);

        if (DUT.dmem[512] === 32'd1)
            $display("PASS: _result_ok = %0d (scalar and QDOT4 agree)", DUT.dmem[512]);
        else
            $display("FAIL: _result_ok = %0d (expected 1)", DUT.dmem[512]);

        if (DUT.dmem[513] === 32'd544)
            $display("PASS: _result_val = %0d (expected 544)", DUT.dmem[513]);
        else
            $display("FAIL: _result_val = %0d (expected 544)", DUT.dmem[513]);

        $finish;
    end
endmodule
