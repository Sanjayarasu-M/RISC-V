// cpu_core_singlecycle.v -- ORIGINAL single-cycle RV32I core + custom-0 (QDOT4) dispatch
// Kept for reference/comparison. cpu_core.v is now the 5-stage pipelined version;
// this file is not compiled into top.v anymore (module renamed to avoid clashing).
module cpu_core_singlecycle (
    input  wire        clk,
    input  wire        rst,

    // instruction memory interface
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_data,

    // data memory interface
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire         dmem_we,
    output wire [3:0]   dmem_be,
    input  wire [31:0]  dmem_rdata
);
    // ---------------- opcodes ----------------
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_IMM    = 7'b0010011;
    localparam OP_REG    = 7'b0110011;
    localparam OP_CUSTOM0= 7'b0001011; // QDOT4 lives here

    // ---------------- PC ----------------
    reg [31:0] pc;
    assign imem_addr = pc;
    wire [31:0] instr = imem_data;

    // ---------------- decode fields ----------------
    wire [6:0] opcode  = instr[6:0];
    wire [4:0] rd_addr = instr[11:7];
    wire [2:0] funct3  = instr[14:12];
    wire [4:0] rs1_addr= instr[19:15];
    wire [4:0] rs2_addr= instr[24:20];
    wire [6:0] funct7  = instr[31:25];

    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    // ---------------- register file ----------------
    wire [31:0] rs1_data, rs2_data, rdsrc_data;
    reg  [31:0] wr_data;
    reg         reg_we;

    regfile RF (
        .clk(clk), .we(reg_we),
        .rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rd_src_addr(rd_addr),
        .wr_addr(rd_addr), .wr_data(wr_data),
        .rs1_data(rs1_data), .rs2_data(rs2_data), .rd_src_data(rdsrc_data)
    );

    // ---------------- ALU op select ----------------
    reg [3:0] alu_op;
    reg       alu_use_imm;
    wire [31:0] alu_imm = (opcode == OP_STORE) ? imm_s : imm_i; // STORE uses S-type immediate!
    wire [31:0] alu_b = alu_use_imm ? alu_imm : rs2_data;
    wire [31:0] alu_result;
    wire        alu_zero;

    alu ALU (.a(rs1_data), .b(alu_b), .op(alu_op), .result(alu_result), .zero(alu_zero));

    always @(*) begin
        alu_use_imm = (opcode == OP_IMM) || (opcode == OP_LOAD) || (opcode == OP_STORE);
        case (opcode)
            OP_REG: begin
                case ({funct7, funct3})
                    {7'b0000000,3'b000}: alu_op = 4'b0000; // ADD
                    {7'b0100000,3'b000}: alu_op = 4'b0001; // SUB
                    {7'b0000000,3'b001}: alu_op = 4'b0010; // SLL
                    {7'b0000000,3'b010}: alu_op = 4'b0011; // SLT
                    {7'b0000000,3'b011}: alu_op = 4'b0100; // SLTU
                    {7'b0000000,3'b100}: alu_op = 4'b0101; // XOR
                    {7'b0000000,3'b101}: alu_op = 4'b0110; // SRL
                    {7'b0100000,3'b101}: alu_op = 4'b0111; // SRA
                    {7'b0000000,3'b110}: alu_op = 4'b1000; // OR
                    {7'b0000000,3'b111}: alu_op = 4'b1001; // AND
                    default:             alu_op = 4'b0000;
                endcase
            end
            OP_IMM: begin
                case (funct3)
                    3'b000: alu_op = 4'b0000; // ADDI
                    3'b010: alu_op = 4'b0011; // SLTI
                    3'b011: alu_op = 4'b0100; // SLTIU
                    3'b100: alu_op = 4'b0101; // XORI
                    3'b110: alu_op = 4'b1000; // ORI
                    3'b111: alu_op = 4'b1001; // ANDI
                    3'b001: alu_op = 4'b0010; // SLLI
                    3'b101: alu_op = instr[30] ? 4'b0111 : 4'b0110; // SRAI/SRLI
                    default: alu_op = 4'b0000;
                endcase
            end
            default: alu_op = 4'b0000; // ADD (used for load/store address calc)
        endcase
    end

    // ---------------- branch condition ----------------
    reg branch_taken;
    always @(*) begin
        case (funct3)
            3'b000: branch_taken = (rs1_data == rs2_data);                 // BEQ
            3'b001: branch_taken = (rs1_data != rs2_data);                 // BNE
            3'b100: branch_taken = ($signed(rs1_data) <  $signed(rs2_data)); // BLT
            3'b101: branch_taken = ($signed(rs1_data) >= $signed(rs2_data)); // BGE
            3'b110: branch_taken = (rs1_data <  rs2_data);                 // BLTU
            3'b111: branch_taken = (rs1_data >= rs2_data);                 // BGEU
            default: branch_taken = 1'b0;
        endcase
    end

    // ---------------- custom QDOT4 ----------------
    wire [31:0] qdot4_result;
    qdot4 QDOT4 (
        .rs1_data(rs1_data), .rs2_data(rs2_data),
        .acc_in(rdsrc_data), .acc_out(qdot4_result)
    );

    // ---------------- data memory ----------------
    assign dmem_addr  = alu_result;
    assign dmem_wdata = rs2_data;
    assign dmem_we    = (opcode == OP_STORE);
    assign dmem_be    = (funct3 == 3'b000) ? 4'b0001 :  // SB
                         (funct3 == 3'b001) ? 4'b0011 :  // SH
                                              4'b1111;    // SW / loads

    reg [31:0] load_data;
    always @(*) begin
        case (funct3)
            3'b000: load_data = {{24{dmem_rdata[7]}},  dmem_rdata[7:0]};   // LB
            3'b001: load_data = {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};  // LH
            3'b010: load_data = dmem_rdata;                                // LW
            3'b100: load_data = {24'b0, dmem_rdata[7:0]};                  // LBU
            3'b101: load_data = {16'b0, dmem_rdata[15:0]};                 // LHU
            default: load_data = dmem_rdata;
        endcase
    end

    // ---------------- writeback mux ----------------
    always @(*) begin
        reg_we = 1'b1;
        case (opcode)
            OP_LUI:     wr_data = imm_u;
            OP_AUIPC:   wr_data = pc + imm_u;
            OP_JAL:     wr_data = pc + 32'd4;
            OP_JALR:    wr_data = pc + 32'd4;
            OP_LOAD:    wr_data = load_data;
            OP_REG:     wr_data = alu_result;
            OP_IMM:     wr_data = alu_result;
            OP_CUSTOM0: wr_data = qdot4_result;   // <-- QDOT4 result
            OP_STORE:   begin wr_data = 32'b0; reg_we = 1'b0; end
            OP_BRANCH:  begin wr_data = 32'b0; reg_we = 1'b0; end
            default:    begin wr_data = 32'b0; reg_we = 1'b0; end
        endcase
    end

    // ---------------- next PC ----------------
    wire [31:0] pc_plus4 = pc + 32'd4;
    wire [31:0] branch_target = pc + imm_b;
    wire [31:0] jal_target    = pc + imm_j;
    wire [31:0] jalr_target   = (rs1_data + imm_i) & ~32'd1;

    always @(posedge clk) begin
        if (rst) begin
            pc <= 32'd0;
        end else begin
            case (opcode)
                OP_JAL:  pc <= jal_target;
                OP_JALR: pc <= jalr_target;
                OP_BRANCH: pc <= branch_taken ? branch_target : pc_plus4;
                default: pc <= pc_plus4;
            endcase
        end
    end

endmodule
