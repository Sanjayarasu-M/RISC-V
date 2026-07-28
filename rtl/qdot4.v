// qdot4.v -- custom AI accelerator instructions, pipelined across EX/MEM
//   QDOT4 rd, rs1, rs2  =>  rd = rd + sum_{i=0..3} rs1[i]*rs2[i]  (signed int8 lanes)
//   QDOT8 rd, rs1, rs2  =>  rd = rd + sum_{i=0..7} A[i]*B[i]
//     where A = rs1 ++ (rs1+1), B = rs2 ++ (rs2+1) (register-pair operands --
//     a 32-bit source field only holds 4 int8 lanes, so the second 4 lanes
//     come from the next register up; see cpu_core.v's rs1_hi/rs2_hi ports
//     and regfile.v). Same opcode as QDOT4 (custom-0), funct3=1 instead of 0.
//
// This is the core "novelty" piece of the project: a tightly-coupled
// SIMD dot-product-accumulate unit for quantized (int8) NN inference,
// analogous to Arm's SDOT instruction / emerging RISC-V matrix extensions.
//
// Split into two combinational stages so the multiply-add tree doesn't sit
// on a single cycle's critical path in the pipelined core:
//   EX  stage: qdot4_mul -- four signed 8x8 multiplies, results registered
//              into EX/MEM. cpu_core.v instantiates this TWICE (lo/hi
//              halves) to get all 8 products QDOT8 needs; QDOT4 only uses
//              the "lo" instance's outputs.
//   MEM stage: qdot_add -- 7-input adder tree + accumulate against rd,
//              registered into MEM/WB. `wide` selects whether the hi-half
//              products (p4..p7) are included (QDOT8) or ignored (QDOT4).
// The result therefore becomes available at the same pipeline point as a
// load's data (end of MEM) for both instructions, and is handled
// identically by the hazard-detection/forwarding logic in cpu_core.v.

module qdot4_mul (
    input  wire [31:0] rs1_data,   // 4x signed int8 packed
    input  wire [31:0] rs2_data,   // 4x signed int8 packed
    output wire signed [15:0] p0,
    output wire signed [15:0] p1,
    output wire signed [15:0] p2,
    output wire signed [15:0] p3
);
    wire signed [7:0] a0 = rs1_data[7:0];
    wire signed [7:0] a1 = rs1_data[15:8];
    wire signed [7:0] a2 = rs1_data[23:16];
    wire signed [7:0] a3 = rs1_data[31:24];

    wire signed [7:0] b0 = rs2_data[7:0];
    wire signed [7:0] b1 = rs2_data[15:8];
    wire signed [7:0] b2 = rs2_data[23:16];
    wire signed [7:0] b3 = rs2_data[31:24];

    assign p0 = a0 * b0;
    assign p1 = a1 * b1;
    assign p2 = a2 * b2;
    assign p3 = a3 * b3;
endmodule

module qdot_add (
    input  wire signed [15:0] p0, p1, p2, p3,   // low 4 lanes (rs1/rs2) -- always summed
    input  wire signed [15:0] p4, p5, p6, p7,   // high 4 lanes (rs1+1/rs2+1) -- QDOT8 only
    input  wire        wide,                     // 1 = QDOT8 (sum all 8 lanes), 0 = QDOT4 (low 4 only)
    input  wire [31:0] acc_in,     // forwarded value of rd (read as source in ID, forwarded in EX)
    output wire [31:0] acc_out     // rd + dot product
);
    wire signed [15:0] p4_eff = wide ? p4 : 16'sd0;
    wire signed [15:0] p5_eff = wide ? p5 : 16'sd0;
    wire signed [15:0] p6_eff = wide ? p6 : 16'sd0;
    wire signed [15:0] p7_eff = wide ? p7 : 16'sd0;

    // 8 lanes of int8*int8 max magnitude 8*128*128 = 131072; 21 bits signed
    // covers that with headroom (same adder serves both QDOT4 and QDOT8).
    wire signed [20:0] dot = p0 + p1 + p2 + p3 + p4_eff + p5_eff + p6_eff + p7_eff;

    assign acc_out = acc_in + {{11{dot[20]}}, dot}; // sign-extend into 32b, add to accumulator
endmodule
