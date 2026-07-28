`timescale 1ns/1ps
module tb_top;
    reg clk = 0;
    reg rst = 1;

    top DUT (.clk(clk), .rst(rst));

    always #5 clk = ~clk; // 100MHz

    initial begin
        $dumpfile("wave.vcd");
        $dumpvars(0, tb_top);

        rst = 1;
        repeat (2) @(posedge clk);
        rst = 0;

        repeat (20) begin
            @(posedge clk);
            $display("t=%0t pc=%h if_id_instr=%h we=%b addr=%h wdata=%h",
                $time, DUT.CORE.pc, DUT.CORE.if_id_instr, DUT.dmem_we, DUT.dmem_addr, DUT.dmem_wdata);
        end

        // dmem[0] should hold the QDOT4 result: 1*1+2*1+3*1+4*1 = 10
        if (DUT.dmem[0] === 32'd10) begin
            $display("PASS: QDOT4 result = %0d (expected 10)", DUT.dmem[0]);
        end else begin
            $display("FAIL: QDOT4 result = %0d (expected 10)", DUT.dmem[0]);
        end

        $display("x1=%0d x2=%0d x3=%0d x4=%h x5=%h x6=%0d",
            DUT.CORE.RF.regs[1], DUT.CORE.RF.regs[2], DUT.CORE.RF.regs[3],
            DUT.CORE.RF.regs[4], DUT.CORE.RF.regs[5], DUT.CORE.RF.regs[6]);

        $finish;
    end
endmodule
