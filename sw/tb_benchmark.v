`timescale 1ns/1ps
// Phase 3: runs the real GCC-compiled kernel (sw/kernel.c) and measures
// elapsed cycles for scalar_dot16 vs qdot4_dot16 by watching for writes to
// the checkpoint addresses defined in sw/link.ld (this core has no
// CSR/rdcycle support, so cycle counting happens here at the testbench
// level instead of in-core).
module tb_benchmark;
    reg clk = 0;
    reg rst = 1;
    integer cycle_count = 0;

    top #(.IMEM_FILE("sw/kernel.hex"), .DMEM_FILE("sw/kernel_data.hex")) DUT (.clk(clk), .rst(rst));

    always #5 clk = ~clk;

    integer ckpt_scalar_start = -1;
    integer ckpt_scalar_end   = -1;
    integer ckpt_qdot4_start  = -1;
    integer ckpt_qdot4_end    = -1;
    integer ckpt_qdot8_start  = -1;
    integer ckpt_qdot8_end    = -1;

    always @(posedge clk) begin
        if (!rst) begin
            cycle_count = cycle_count + 1;
            if (DUT.dmem_we) begin
                case (DUT.dmem_addr)
                    32'h00000810: if (ckpt_scalar_start < 0) ckpt_scalar_start = cycle_count;
                    32'h00000814: if (ckpt_scalar_end   < 0) ckpt_scalar_end   = cycle_count;
                    32'h00000818: if (ckpt_qdot4_start  < 0) ckpt_qdot4_start  = cycle_count;
                    32'h0000081C: if (ckpt_qdot4_end    < 0) ckpt_qdot4_end    = cycle_count;
                    32'h00000820: if (ckpt_qdot8_start  < 0) ckpt_qdot8_start  = cycle_count;
                    32'h00000824: if (ckpt_qdot8_end    < 0) ckpt_qdot8_end    = cycle_count;
                    default: ;
                endcase
            end
        end
    end

    integer scalar_cycles, qdot4_cycles, qdot8_cycles;
    real speedup4, speedup8, speedup8v4;

    initial begin
        rst = 1;
        repeat (2) @(posedge clk);
        rst = 0;

        repeat (5000) @(posedge clk);

        if (DUT.dmem[512] === 32'd1)
            $display("PASS: _result_ok = %0d (scalar, QDOT4, and QDOT8 agree)", DUT.dmem[512]);
        else
            $display("FAIL: _result_ok = %0d (expected 1)", DUT.dmem[512]);

        if (DUT.dmem[513] === 32'd544)
            $display("PASS: _result_val (QDOT4) = %0d (expected 544)", DUT.dmem[513]);
        else
            $display("FAIL: _result_val (QDOT4) = %0d (expected 544)", DUT.dmem[513]);

        if (DUT.dmem[515] === 32'd544)
            $display("PASS: _result_val_qdot8 = %0d (expected 544)", DUT.dmem[515]);
        else
            $display("FAIL: _result_val_qdot8 = %0d (expected 544)", DUT.dmem[515]);

        if (ckpt_scalar_start < 0 || ckpt_scalar_end < 0 || ckpt_qdot4_start < 0 || ckpt_qdot4_end < 0 ||
            ckpt_qdot8_start < 0 || ckpt_qdot8_end < 0) begin
            $display("FAIL: one or more checkpoints never fired (scalar_start=%0d scalar_end=%0d qdot4_start=%0d qdot4_end=%0d qdot8_start=%0d qdot8_end=%0d)",
                ckpt_scalar_start, ckpt_scalar_end, ckpt_qdot4_start, ckpt_qdot4_end, ckpt_qdot8_start, ckpt_qdot8_end);
        end else begin
            scalar_cycles = ckpt_scalar_end - ckpt_scalar_start;
            qdot4_cycles  = ckpt_qdot4_end  - ckpt_qdot4_start;
            qdot8_cycles  = ckpt_qdot8_end  - ckpt_qdot8_start;
            speedup4   = scalar_cycles * 1.0 / qdot4_cycles;
            speedup8   = scalar_cycles * 1.0 / qdot8_cycles;
            speedup8v4 = qdot4_cycles  * 1.0 / qdot8_cycles;

            $display("---------------------------------------------------");
            $display(" 64-element int8 dot product, pipelined 5-stage core");
            $display("---------------------------------------------------");
            $display(" scalar_dot16 (RV32I + soft-mul) : %0d cycles", scalar_cycles);
            $display(" qdot4_dot16  (QDOT4 accelerated): %0d cycles", qdot4_cycles);
            $display(" qdot8_dot16  (QDOT8 accelerated): %0d cycles", qdot8_cycles);
            $display(" speedup (QDOT4 vs scalar)       : %0.2fx", speedup4);
            $display(" speedup (QDOT8 vs scalar)       : %0.2fx", speedup8);
            $display(" speedup (QDOT8 vs QDOT4)        : %0.2fx", speedup8v4);
            $display("---------------------------------------------------");
        end

        $finish;
    end
endmodule
