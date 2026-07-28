// regfile.v -- 32x32-bit register file, x0 hardwired to zero
// 5 read ports (rs1, rs2, rd-as-source for accumulate instructions, and
// rs1_hi/rs2_hi -- the "+1" register-pair partners used by QDOT8 to get a
// second 4-lane int8 vector out of a single R-type source field) plus 1
// write port.
//
// Write-through bypass: if the WB stage is writing the same register that
// ID is reading this cycle, the read ports return the new data instead of
// the stale array contents (the array itself only updates on the next
// edge). Needed once the core is pipelined, since WB and ID now happen in
// the same cycle for instructions three stages apart.
module regfile (
    input  wire        clk,
    input  wire         we,
    input  wire [4:0]   rs1_addr,
    input  wire [4:0]   rs2_addr,
    input  wire [4:0]   rd_src_addr,   // rd read as a source (for QDOT4/QDOT8 accumulate)
    input  wire [4:0]   rs1_hi_addr,   // rs1+1 (QDOT8 only)
    input  wire [4:0]   rs2_hi_addr,   // rs2+1 (QDOT8 only)
    input  wire [4:0]   wr_addr,
    input  wire [31:0]  wr_data,
    output wire [31:0]  rs1_data,
    output wire [31:0]  rs2_data,
    output wire [31:0]  rd_src_data,
    output wire [31:0]  rs1_hi_data,
    output wire [31:0]  rs2_hi_data
);
    reg [31:0] regs [1:31];  // x0 not stored, always reads 0

    wire wr_fires = we && (wr_addr != 5'd0);

    assign rs1_data    = (rs1_addr == 5'd0) ? 32'd0 :
                          (wr_fires && wr_addr == rs1_addr) ? wr_data : regs[rs1_addr];
    assign rs2_data    = (rs2_addr == 5'd0) ? 32'd0 :
                          (wr_fires && wr_addr == rs2_addr) ? wr_data : regs[rs2_addr];
    assign rd_src_data = (rd_src_addr == 5'd0) ? 32'd0 :
                          (wr_fires && wr_addr == rd_src_addr) ? wr_data : regs[rd_src_addr];
    assign rs1_hi_data = (rs1_hi_addr == 5'd0) ? 32'd0 :
                          (wr_fires && wr_addr == rs1_hi_addr) ? wr_data : regs[rs1_hi_addr];
    assign rs2_hi_data = (rs2_hi_addr == 5'd0) ? 32'd0 :
                          (wr_fires && wr_addr == rs2_hi_addr) ? wr_data : regs[rs2_hi_addr];

    always @(posedge clk) begin
        if (wr_fires)
            regs[wr_addr] <= wr_data;
    end
endmodule
