`timescale 1ns/1ps
// QDOT8 register-pair (rs1_hi/rs2_hi) hazard/forwarding test.
// Expects mem[0] == 62 (load-produced rs1_hi, stall + MEM/WB forward) and
// mem[1] == 150 (ALU-produced rs2_hi, EX/MEM forward, no stall).
module tb_hazard_qdot8_hi;
    reg clk = 0;
    reg rst = 1;

    top #(.IMEM_FILE("tests/hazard_qdot8_hi.hex")) DUT (.clk(clk), .rst(rst));

    always #5 clk = ~clk;

    initial begin
        rst = 1;
        repeat (2) @(posedge clk);
        rst = 0;

        repeat (50) @(posedge clk);

        if (DUT.dmem[2] === 32'd62) begin
            $display("PASS: hazard_qdot8_hi part1 (rs1_hi load-stall) result = %0d (expected 62)", DUT.dmem[2]);
        end else begin
            $display("FAIL: hazard_qdot8_hi part1 (rs1_hi load-stall) result = %0d (expected 62)", DUT.dmem[2]);
        end

        if (DUT.dmem[1] === 32'd150) begin
            $display("PASS: hazard_qdot8_hi part2 (rs2_hi EX/MEM-forward) result = %0d (expected 150)", DUT.dmem[1]);
        end else begin
            $display("FAIL: hazard_qdot8_hi part2 (rs2_hi EX/MEM-forward) result = %0d (expected 150)", DUT.dmem[1]);
        end
        $finish;
    end
endmodule
