// cpu_core.v -- 5-stage pipelined RV32I core + custom-0 (QDOT4/QDOT8) dispatch
//
// Stages: IF -> ID -> EX -> MEM -> WB
//
// Hazard handling:
//   - Data hazards: full forwarding from EX/MEM and MEM/WB back into EX
//     (operands rs1, rs2, rd-as-source for QDOT4/QDOT8's accumulate input,
//     and rs1_hi/rs2_hi -- QDOT8's register-pair partners).
//   - Loads, QDOT4, and QDOT8 all produce their result at the END of MEM
//     (like a classic load), so a 1-cycle stall (bubble) is inserted
//     whenever the very next instruction needs that value -- the
//     "load-use hazard", generalized here to also cover QDOT4/QDOT8-use.
//   - Control hazards: predict not-taken. BRANCH and JALR resolve in EX
//     (using forwarded operands), costing a 2-bubble flush when
//     redirected. JAL is unconditional and needs no registers, so it
//     resolves in ID, costing only a 1-bubble flush.
//
// The QDOT4/QDOT8 datapath is itself pipelined across EX (multiply) and MEM
// (adder tree + accumulate) -- see qdot4.v -- so its result lands at the
// same pipeline point as a load and is handled by the same hazard logic.
//
// QDOT8 (funct3=1, same custom-0 opcode as QDOT4) widens to 8 int8 lanes.
// A 32-bit source register only holds 4 lanes, so QDOT8 uses the
// register-pair trick common to ISAs facing the same problem (e.g. RISC-V
// Zdinx, ARM register pairs): rs1/rs2 supply the low 4 lanes as before, and
// rs1+1/rs2+1 (read via 2 extra regfile ports) supply the high 4 lanes.
// rs1=x31 (or rs2=x31) wraps to x0 for the "+1" half -- avoid using x31 as
// a QDOT8 operand. QDOT4's multiply unit (qdot4_mul) is instantiated twice
// (lo/hi) to get all 8 products; a single wide-capable adder (qdot_add)
// sums 4 or 8 of them depending on which instruction is in MEM.
//
// NOTE on file layout: Icarus Verilog's elaborator wants every signal's
// declaration to textually precede its first use within the module, which
// is stricter than the LRM requires. Since PC-redirect/stall are feedback
// signals computed in later stages (EX) but consumed by an earlier stage
// (IF), all pipeline registers and those feedback wires are declared in
// one block up front; the logic below just drives them.
//
// Module ports are unchanged from the single-cycle version, so top.v
// does not need to change.
module cpu_core (
    input  wire        clk,
    input  wire        rst,

    // instruction memory interface
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_data,
    output wire         imem_stall, // freeze imem's registered output during a hazard stall (see IF stage comment)

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
    localparam OP_CUSTOM0= 7'b0001011; // QDOT4 (funct3=0) / QDOT8 (funct3=1) live here

    localparam [31:0] NOP_INSTR = 32'h00000013; // addi x0,x0,0

    // ALU op encoding (must match alu.v)
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_SLL  = 4'b0010;
    localparam ALU_SLT  = 4'b0011;
    localparam ALU_SLTU = 4'b0100;
    localparam ALU_XOR  = 4'b0101;
    localparam ALU_SRL  = 4'b0110;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_OR   = 4'b1000;
    localparam ALU_AND  = 4'b1001;

    // ALU 'a' operand source select
    localparam ALU_A_RS1  = 2'd0;
    localparam ALU_A_PC   = 2'd1;
    localparam ALU_A_ZERO = 2'd2;

    // writeback source select
    localparam WB_ALU   = 3'd0;
    localparam WB_MEM   = 3'd1;
    localparam WB_QDOT  = 3'd2;   // shared by QDOT4 and QDOT8
    localparam WB_PC4   = 3'd3;

    // =====================================================================
    // Pipeline register + feedback-signal declarations (see NOTE above)
    // =====================================================================
    reg [31:0] pc;

    reg [31:0] pc_bram;  // pc, delayed 1 cycle to stay aligned with imem_data's BRAM read latency
    reg [31:0] if_id_pc;
    reg [31:0] if_id_instr;

    reg [31:0] id_ex_pc;
    reg [4:0]  id_ex_rs1_addr, id_ex_rs2_addr, id_ex_rd_addr;
    reg [4:0]  id_ex_rs1_hi_addr, id_ex_rs2_hi_addr;
    reg [31:0] id_ex_rs1_data, id_ex_rs2_data, id_ex_rdsrc_data;
    reg [31:0] id_ex_rs1_hi_data, id_ex_rs2_hi_data;
    reg [31:0] id_ex_imm_sel;
    reg [3:0]  id_ex_alu_op;
    reg        id_ex_alu_use_imm;
    reg [1:0]  id_ex_alu_a_src;
    reg        id_ex_reg_we;
    reg [2:0]  id_ex_wb_sel;
    reg        id_ex_is_load, id_ex_is_store, id_ex_is_branch, id_ex_is_jalr, id_ex_is_qdot4, id_ex_is_qdot8;
    reg [2:0]  id_ex_funct3;

    reg [31:0] ex_mem_pc;
    reg [31:0] ex_mem_alu_result;
    reg [31:0] ex_mem_store_data;
    reg [4:0]  ex_mem_rd_addr;
    reg        ex_mem_reg_we;
    reg [2:0]  ex_mem_wb_sel;
    reg        ex_mem_is_load, ex_mem_is_store, ex_mem_is_qdot4, ex_mem_is_qdot8;
    reg [2:0]  ex_mem_funct3;
    reg signed [15:0] ex_mem_p0, ex_mem_p1, ex_mem_p2, ex_mem_p3;
    reg signed [15:0] ex_mem_p4, ex_mem_p5, ex_mem_p6, ex_mem_p7;
    reg [31:0] ex_mem_qdot_acc_in;

    reg [31:0] mem_wb_pc;
    reg [31:0] mem_wb_alu_result;
    reg [31:0] mem_wb_qdot_result;
    reg [4:0]  mem_wb_rd_addr;
    reg        mem_wb_reg_we;
    reg [2:0]  mem_wb_wb_sel;
    reg [2:0]  mem_wb_funct3;      // needed to interpret dmem_rdata, which (BRAM read) only becomes valid this stage
    reg [1:0]  mem_wb_byte_offset;

    // feedback signals: driven by later stages, consumed by earlier ones
    wire        flush_ex;
    wire [31:0] ex_redirect_target;
    wire        jal_taken_id;
    wire [31:0] jal_target_d;
    wire        hazard_stall;
    reg  [31:0] wb_wr_data;

    // =====================================================================
    // IF stage
    // =====================================================================
    // imem is a synchronous-read (BRAM-inferring) memory: imem_data reflects
    // imem[pc] one cycle AFTER pc is presented, not combinationally. This
    // is effectively a genuine IF1/IF2 split: pc_bram tracks pc through that
    // one-cycle BRAM latency (unconditionally -- pc itself already encodes
    // "held during stall" by not changing, so re-presenting it just re-reads
    // the same instruction, same as the BRAM's own behavior), and
    // if_id_instr/if_id_pc are the real IF/ID pipeline register, structured
    // exactly as they would be for a combinational-read memory but sourced
    // from the (now-delayed) imem_data/pc_bram instead.
    //
    // This buffering register is NOT optional: without it, a cycle where a
    // stall clears would consume whatever imem_data currently holds even
    // though it hasn't caught up yet to the address pc just advanced past,
    // silently dropping the real next instruction one BRAM-latency cycle
    // later. (Found by exactly that failure in the back-to-back QDOT4
    // hazard test -- see tests/tb_hazard_qdot4.v.)
    //
    // That still isn't the whole fix: pc leads if_id_instr by TWO cycles now
    // (one for imem's BRAM latency, one for this buffer), so by the time a
    // hazard is detectable (the conflicting instruction has to actually
    // reach if_id_instr first), pc has already raced ahead and fetched the
    // NEXT instruction too, into imem_data. If imem_data keeps advancing
    // unconditionally while if_id_instr holds, that in-flight fetch gets
    // silently overwritten and lost. So imem_data's own register must ALSO
    // freeze during a hazard stall (imem_stall, gating top.v's BRAM read) --
    // not just pc -- to preserve it until if_id_instr is ready to accept it.
    assign imem_stall = hazard_stall;
    assign imem_addr = pc;
    wire [31:0] pc_plus4_if = pc + 32'd4;

    always @(posedge clk) begin
        if (rst)                pc <= 32'd0;
        else if (flush_ex)      pc <= ex_redirect_target;
        else if (jal_taken_id)  pc <= jal_target_d;
        else if (hazard_stall)  pc <= pc;                 // frozen
        else                    pc <= pc_plus4_if;
    end

    always @(posedge clk) begin
        if (rst) pc_bram <= 32'd0;
        else     pc_bram <= pc;
    end

    // A redirect (flush_ex/jal_taken_id) squashes if_id_instr immediately,
    // but pc leads if_id_instr by TWO cycles now, not one: there's a second
    // wrong-path instruction already sitting in imem_data (fetched the
    // cycle before the redirect was known) that hasn't reached if_id_instr
    // yet. squash_echo re-asserts the squash one cycle later to catch it --
    // without this, that stale fetch gets consumed right after the "real"
    // squash cycle ends. (Same root cause as the QDOT4 hazard bug above,
    // just on the control-flow-redirect path instead of the stall path;
    // found the same way, in tests/tb_hazard_branch.v against sw/kernel.hex
    // where crt0's branch-taken bss-zero-skip landed one instruction short.)
    reg squash_echo;
    always @(posedge clk) begin
        if (rst) squash_echo <= 1'b0;
        else     squash_echo <= (flush_ex || jal_taken_id);
    end

    // ---------------- IF/ID pipeline register ----------------
    always @(posedge clk) begin
        if (rst) begin
            if_id_instr <= NOP_INSTR; if_id_pc <= 32'd0;
        end else if (flush_ex || jal_taken_id || squash_echo) begin
            if_id_instr <= NOP_INSTR; if_id_pc <= 32'd0;   // squash wrong-path fetch(es)
        end else if (hazard_stall) begin
            if_id_instr <= if_id_instr; if_id_pc <= if_id_pc; // hold (re-decode next cycle)
        end else begin
            if_id_instr <= imem_data; if_id_pc <= pc_bram;
        end
    end

    // =====================================================================
    // ID stage
    // =====================================================================
    wire [6:0] opcode_d  = if_id_instr[6:0];
    wire [4:0] rd_d      = if_id_instr[11:7];
    wire [2:0] funct3_d  = if_id_instr[14:12];
    wire [4:0] rs1_d     = if_id_instr[19:15];
    wire [4:0] rs2_d     = if_id_instr[24:20];
    wire [6:0] funct7_d  = if_id_instr[31:25];

    // QDOT8's register-pair partners: rs1+1 / rs2+1 (5-bit wraparound, so
    // x31 wraps to x0 -- documented limitation, see header comment).
    wire [4:0] rs1_hi_d = rs1_d + 5'd1;
    wire [4:0] rs2_hi_d = rs2_d + 5'd1;

    wire [31:0] imm_i_d = {{20{if_id_instr[31]}}, if_id_instr[31:20]};
    wire [31:0] imm_s_d = {{20{if_id_instr[31]}}, if_id_instr[31:25], if_id_instr[11:7]};
    wire [31:0] imm_b_d = {{19{if_id_instr[31]}}, if_id_instr[31], if_id_instr[7], if_id_instr[30:25], if_id_instr[11:8], 1'b0};
    wire [31:0] imm_u_d = {if_id_instr[31:12], 12'b0};
    wire [31:0] imm_j_d = {{11{if_id_instr[31]}}, if_id_instr[31], if_id_instr[19:12], if_id_instr[20], if_id_instr[30:21], 1'b0};

    reg [31:0] imm_sel_d;
    always @(*) begin
        case (opcode_d)
            OP_STORE:          imm_sel_d = imm_s_d;
            OP_BRANCH:         imm_sel_d = imm_b_d;
            OP_LUI, OP_AUIPC:  imm_sel_d = imm_u_d;
            OP_JAL:            imm_sel_d = imm_j_d;
            default:           imm_sel_d = imm_i_d; // IMM, LOAD, JALR
        endcase
    end

    // JAL resolves here in ID: target needs only PC + immediate, no registers.
    assign jal_target_d = if_id_pc + imm_j_d;
    assign jal_taken_id = (opcode_d == OP_JAL);

    // register file (written from WB stage)
    wire [31:0] rs1_data_d, rs2_data_d, rdsrc_data_d, rs1_hi_data_d, rs2_hi_data_d;
    regfile RF (
        .clk(clk), .we(mem_wb_reg_we),
        .rs1_addr(rs1_d), .rs2_addr(rs2_d), .rd_src_addr(rd_d),
        .rs1_hi_addr(rs1_hi_d), .rs2_hi_addr(rs2_hi_d),
        .wr_addr(mem_wb_rd_addr), .wr_data(wb_wr_data),
        .rs1_data(rs1_data_d), .rs2_data(rs2_data_d), .rd_src_data(rdsrc_data_d),
        .rs1_hi_data(rs1_hi_data_d), .rs2_hi_data(rs2_hi_data_d)
    );

    // ---------------- control decode ----------------
    reg [3:0] alu_op_d;
    reg       alu_use_imm_d;
    reg [1:0] alu_a_src_d;
    reg       reg_we_d;
    reg [2:0] wb_sel_d;
    reg       is_load_d, is_store_d, is_branch_d, is_jalr_d, is_qdot4_d, is_qdot8_d;
    reg       uses_rs1_d, uses_rs2_d, uses_rdsrc_d, uses_rs1_hi_d, uses_rs2_hi_d;

    always @(*) begin
        alu_use_imm_d = 1'b0;
        alu_a_src_d   = ALU_A_RS1;
        reg_we_d      = 1'b0;
        wb_sel_d      = WB_ALU;
        is_load_d     = 1'b0;
        is_store_d    = 1'b0;
        is_branch_d   = 1'b0;
        is_jalr_d     = 1'b0;
        is_qdot4_d    = 1'b0;
        is_qdot8_d    = 1'b0;
        uses_rs1_d    = 1'b0;
        uses_rs2_d    = 1'b0;
        uses_rdsrc_d  = 1'b0;
        uses_rs1_hi_d = 1'b0;
        uses_rs2_hi_d = 1'b0;
        alu_op_d      = ALU_ADD;

        case (opcode_d)
            OP_LUI: begin
                alu_a_src_d = ALU_A_ZERO; alu_use_imm_d = 1'b1; alu_op_d = ALU_ADD;
                reg_we_d = 1'b1; wb_sel_d = WB_ALU;
            end
            OP_AUIPC: begin
                alu_a_src_d = ALU_A_PC; alu_use_imm_d = 1'b1; alu_op_d = ALU_ADD;
                reg_we_d = 1'b1; wb_sel_d = WB_ALU;
            end
            OP_JAL: begin
                reg_we_d = 1'b1; wb_sel_d = WB_PC4;
            end
            OP_JALR: begin
                is_jalr_d = 1'b1; uses_rs1_d = 1'b1;
                reg_we_d = 1'b1; wb_sel_d = WB_PC4;
            end
            OP_BRANCH: begin
                is_branch_d = 1'b1; uses_rs1_d = 1'b1; uses_rs2_d = 1'b1;
            end
            OP_LOAD: begin
                is_load_d = 1'b1; uses_rs1_d = 1'b1; alu_use_imm_d = 1'b1;
                reg_we_d = 1'b1; wb_sel_d = WB_MEM; alu_op_d = ALU_ADD;
            end
            OP_STORE: begin
                is_store_d = 1'b1; uses_rs1_d = 1'b1; uses_rs2_d = 1'b1;
                alu_use_imm_d = 1'b1; alu_op_d = ALU_ADD;
            end
            OP_IMM: begin
                uses_rs1_d = 1'b1; alu_use_imm_d = 1'b1;
                reg_we_d = 1'b1; wb_sel_d = WB_ALU;
                case (funct3_d)
                    3'b000: alu_op_d = ALU_ADD;  // ADDI
                    3'b010: alu_op_d = ALU_SLT;  // SLTI
                    3'b011: alu_op_d = ALU_SLTU; // SLTIU
                    3'b100: alu_op_d = ALU_XOR;  // XORI
                    3'b110: alu_op_d = ALU_OR;   // ORI
                    3'b111: alu_op_d = ALU_AND;  // ANDI
                    3'b001: alu_op_d = ALU_SLL;  // SLLI
                    3'b101: alu_op_d = if_id_instr[30] ? ALU_SRA : ALU_SRL; // SRAI/SRLI
                    default: alu_op_d = ALU_ADD;
                endcase
            end
            OP_REG: begin
                uses_rs1_d = 1'b1; uses_rs2_d = 1'b1;
                reg_we_d = 1'b1; wb_sel_d = WB_ALU;
                case ({funct7_d, funct3_d})
                    {7'b0000000,3'b000}: alu_op_d = ALU_ADD;
                    {7'b0100000,3'b000}: alu_op_d = ALU_SUB;
                    {7'b0000000,3'b001}: alu_op_d = ALU_SLL;
                    {7'b0000000,3'b010}: alu_op_d = ALU_SLT;
                    {7'b0000000,3'b011}: alu_op_d = ALU_SLTU;
                    {7'b0000000,3'b100}: alu_op_d = ALU_XOR;
                    {7'b0000000,3'b101}: alu_op_d = ALU_SRL;
                    {7'b0100000,3'b101}: alu_op_d = ALU_SRA;
                    {7'b0000000,3'b110}: alu_op_d = ALU_OR;
                    {7'b0000000,3'b111}: alu_op_d = ALU_AND;
                    default:             alu_op_d = ALU_ADD;
                endcase
            end
            OP_CUSTOM0: begin
                // QDOT4 (funct3=0) and QDOT8 (funct3=1) both accumulate into
                // rd from rs1/rs2; QDOT8 additionally needs the rs1+1/rs2+1
                // register-pair partners for its extra 4 lanes.
                uses_rs1_d = 1'b1; uses_rs2_d = 1'b1; uses_rdsrc_d = 1'b1;
                reg_we_d = 1'b1; wb_sel_d = WB_QDOT;
                if (funct3_d == 3'b001) begin
                    is_qdot8_d    = 1'b1;
                    uses_rs1_hi_d = 1'b1;
                    uses_rs2_hi_d = 1'b1;
                end else begin
                    is_qdot4_d = 1'b1;
                end
            end
            default: ; // unknown/NOP: no writeback, no side effects
        endcase
    end

    // ---------------- hazard detection (load-use / qdot-use stall) ----------------
    // If the instruction ahead of us in ID/EX is a load, QDOT4, or QDOT8,
    // its result isn't ready until the end of MEM -- one cycle later than
    // forwarding from EX/MEM can supply. If we need that register right
    // now (including as a QDOT8 register-pair partner), stall.
    assign hazard_stall =
        (id_ex_is_load || id_ex_is_qdot4 || id_ex_is_qdot8) && (id_ex_rd_addr != 5'd0) &&
        ( (uses_rs1_d    && (id_ex_rd_addr == rs1_d))    ||
          (uses_rs2_d    && (id_ex_rd_addr == rs2_d))    ||
          (uses_rdsrc_d  && (id_ex_rd_addr == rd_d))     ||
          (uses_rs1_hi_d && (id_ex_rd_addr == rs1_hi_d)) ||
          (uses_rs2_hi_d && (id_ex_rd_addr == rs2_hi_d)) );

    // ---------------- ID/EX pipeline register ----------------
    always @(posedge clk) begin
        if (rst || flush_ex || hazard_stall) begin
            // bubble: no writeback, no memory/branch side effects
            id_ex_reg_we    <= 1'b0;
            id_ex_is_load   <= 1'b0;
            id_ex_is_store  <= 1'b0;
            id_ex_is_branch <= 1'b0;
            id_ex_is_jalr   <= 1'b0;
            id_ex_is_qdot4  <= 1'b0;
            id_ex_is_qdot8  <= 1'b0;
            id_ex_rd_addr   <= 5'd0;
            id_ex_wb_sel    <= WB_ALU;
        end else begin
            id_ex_pc          <= if_id_pc;
            id_ex_rs1_addr    <= rs1_d;
            id_ex_rs2_addr    <= rs2_d;
            id_ex_rd_addr     <= rd_d;
            id_ex_rs1_hi_addr <= rs1_hi_d;
            id_ex_rs2_hi_addr <= rs2_hi_d;
            id_ex_rs1_data    <= rs1_data_d;
            id_ex_rs2_data    <= rs2_data_d;
            id_ex_rdsrc_data  <= rdsrc_data_d;
            id_ex_rs1_hi_data <= rs1_hi_data_d;
            id_ex_rs2_hi_data <= rs2_hi_data_d;
            id_ex_imm_sel     <= imm_sel_d;
            id_ex_alu_op      <= alu_op_d;
            id_ex_alu_use_imm <= alu_use_imm_d;
            id_ex_alu_a_src   <= alu_a_src_d;
            id_ex_reg_we      <= reg_we_d;
            id_ex_wb_sel      <= wb_sel_d;
            id_ex_is_load     <= is_load_d;
            id_ex_is_store    <= is_store_d;
            id_ex_is_branch   <= is_branch_d;
            id_ex_is_jalr     <= is_jalr_d;
            id_ex_is_qdot4    <= is_qdot4_d;
            id_ex_is_qdot8    <= is_qdot8_d;
            id_ex_funct3      <= funct3_d;
        end
    end

    // =====================================================================
    // EX stage
    // =====================================================================
    // Forwarding source validity: EX/MEM only holds a usable ALU-class result
    // (loads, QDOT4, and QDOT8 aren't done until the end of MEM, so their
    // EX/MEM slot isn't a valid forwarding source yet -- MEM/WB is, one
    // cycle later).
    wire ex_mem_fwd_valid  = ex_mem_reg_we && (ex_mem_rd_addr != 5'd0) && !ex_mem_is_load && !ex_mem_is_qdot4 && !ex_mem_is_qdot8;
    wire mem_wb_fwd_valid  = mem_wb_reg_we && (mem_wb_rd_addr != 5'd0);

    reg [31:0] fwd_a, fwd_b, fwd_c, fwd_a_hi, fwd_b_hi;
    always @(*) begin
        if (ex_mem_fwd_valid && (ex_mem_rd_addr == id_ex_rs1_addr))
            fwd_a = ex_mem_alu_result;
        else if (mem_wb_fwd_valid && (mem_wb_rd_addr == id_ex_rs1_addr))
            fwd_a = wb_wr_data;
        else
            fwd_a = id_ex_rs1_data;

        if (ex_mem_fwd_valid && (ex_mem_rd_addr == id_ex_rs2_addr))
            fwd_b = ex_mem_alu_result;
        else if (mem_wb_fwd_valid && (mem_wb_rd_addr == id_ex_rs2_addr))
            fwd_b = wb_wr_data;
        else
            fwd_b = id_ex_rs2_data;

        if (ex_mem_fwd_valid && (ex_mem_rd_addr == id_ex_rd_addr))
            fwd_c = ex_mem_alu_result;
        else if (mem_wb_fwd_valid && (mem_wb_rd_addr == id_ex_rd_addr))
            fwd_c = wb_wr_data;
        else
            fwd_c = id_ex_rdsrc_data;

        if (ex_mem_fwd_valid && (ex_mem_rd_addr == id_ex_rs1_hi_addr))
            fwd_a_hi = ex_mem_alu_result;
        else if (mem_wb_fwd_valid && (mem_wb_rd_addr == id_ex_rs1_hi_addr))
            fwd_a_hi = wb_wr_data;
        else
            fwd_a_hi = id_ex_rs1_hi_data;

        if (ex_mem_fwd_valid && (ex_mem_rd_addr == id_ex_rs2_hi_addr))
            fwd_b_hi = ex_mem_alu_result;
        else if (mem_wb_fwd_valid && (mem_wb_rd_addr == id_ex_rs2_hi_addr))
            fwd_b_hi = wb_wr_data;
        else
            fwd_b_hi = id_ex_rs2_hi_data;
    end

    wire [31:0] alu_a = (id_ex_alu_a_src == ALU_A_PC)   ? id_ex_pc :
                         (id_ex_alu_a_src == ALU_A_ZERO) ? 32'd0   :
                                                            fwd_a;
    wire [31:0] alu_b = id_ex_alu_use_imm ? id_ex_imm_sel : fwd_b;

    wire [31:0] alu_result_ex;
    wire        alu_zero_ex;
    alu ALU (.a(alu_a), .b(alu_b), .op(id_ex_alu_op), .result(alu_result_ex), .zero(alu_zero_ex));

    reg branch_taken_ex;
    always @(*) begin
        case (id_ex_funct3)
            3'b000: branch_taken_ex = (fwd_a == fwd_b);                   // BEQ
            3'b001: branch_taken_ex = (fwd_a != fwd_b);                   // BNE
            3'b100: branch_taken_ex = ($signed(fwd_a) <  $signed(fwd_b)); // BLT
            3'b101: branch_taken_ex = ($signed(fwd_a) >= $signed(fwd_b)); // BGE
            3'b110: branch_taken_ex = (fwd_a <  fwd_b);                   // BLTU
            3'b111: branch_taken_ex = (fwd_a >= fwd_b);                   // BGEU
            default: branch_taken_ex = 1'b0;
        endcase
    end

    wire [31:0] branch_target_ex = id_ex_pc + id_ex_imm_sel;
    wire [31:0] jalr_target_ex   = (fwd_a + id_ex_imm_sel) & ~32'd1;

    assign flush_ex = (id_ex_is_branch && branch_taken_ex) || id_ex_is_jalr;
    assign ex_redirect_target = id_ex_is_jalr ? jalr_target_ex : branch_target_ex;

    wire [31:0] store_data_ex = fwd_b; // store always writes rs2, regardless of alu_use_imm

    // QDOT4/QDOT8 multiply stage (EX half of the pipelined unit): the same
    // qdot4_mul module is instantiated twice -- once for the low 4 lanes
    // (rs1/rs2, used by both instructions) and once for the high 4 lanes
    // (rs1_hi/rs2_hi, QDOT8 only; for QDOT4 these outputs are simply
    // discarded by qdot_add's wide=0 select in MEM).
    wire signed [15:0] qdot_p0, qdot_p1, qdot_p2, qdot_p3;
    qdot4_mul QDOT_MUL_LO (
        .rs1_data(fwd_a), .rs2_data(fwd_b),
        .p0(qdot_p0), .p1(qdot_p1), .p2(qdot_p2), .p3(qdot_p3)
    );

    wire signed [15:0] qdot_p4, qdot_p5, qdot_p6, qdot_p7;
    qdot4_mul QDOT_MUL_HI (
        .rs1_data(fwd_a_hi), .rs2_data(fwd_b_hi),
        .p0(qdot_p4), .p1(qdot_p5), .p2(qdot_p6), .p3(qdot_p7)
    );

    // ---------------- EX/MEM pipeline register ----------------
    always @(posedge clk) begin
        if (rst) begin
            ex_mem_reg_we   <= 1'b0;
            ex_mem_is_load  <= 1'b0;
            ex_mem_is_store <= 1'b0;
            ex_mem_is_qdot4 <= 1'b0;
            ex_mem_is_qdot8 <= 1'b0;
            ex_mem_rd_addr  <= 5'd0;
        end else begin
            ex_mem_pc           <= id_ex_pc;
            ex_mem_alu_result   <= alu_result_ex;
            ex_mem_store_data   <= store_data_ex;
            ex_mem_rd_addr      <= id_ex_rd_addr;
            ex_mem_reg_we       <= id_ex_reg_we;
            ex_mem_wb_sel       <= id_ex_wb_sel;
            ex_mem_is_load      <= id_ex_is_load;
            ex_mem_is_store     <= id_ex_is_store;
            ex_mem_is_qdot4     <= id_ex_is_qdot4;
            ex_mem_is_qdot8     <= id_ex_is_qdot8;
            ex_mem_funct3       <= id_ex_funct3;
            ex_mem_p0           <= qdot_p0;
            ex_mem_p1           <= qdot_p1;
            ex_mem_p2           <= qdot_p2;
            ex_mem_p3           <= qdot_p3;
            ex_mem_p4           <= qdot_p4;
            ex_mem_p5           <= qdot_p5;
            ex_mem_p6           <= qdot_p6;
            ex_mem_p7           <= qdot_p7;
            ex_mem_qdot_acc_in  <= fwd_c;
        end
    end

    // =====================================================================
    // MEM stage
    // =====================================================================
    // dmem is a word-addressed array (top.v indexes it with addr[31:2]), so
    // sub-word loads/stores must select/place the right byte lane using the
    // address's low 2 bits -- NOT always lane 0 of the containing word.
    assign dmem_addr = ex_mem_alu_result;
    assign dmem_we   = ex_mem_is_store;

    wire [1:0] mem_byte_offset = ex_mem_alu_result[1:0];

    reg [31:0] dmem_wdata_r;
    reg [3:0]  dmem_be_r;
    always @(*) begin
        case (ex_mem_funct3)
            3'b001: begin // SH (halfword-aligned: offset is 0 or 2)
                if (mem_byte_offset[1]) begin
                    dmem_be_r    = 4'b1100;
                    dmem_wdata_r = {ex_mem_store_data[15:0], 16'b0};
                end else begin
                    dmem_be_r    = 4'b0011;
                    dmem_wdata_r = {16'b0, ex_mem_store_data[15:0]};
                end
            end
            3'b000: begin // SB
                case (mem_byte_offset)
                    2'b00: begin dmem_be_r = 4'b0001; dmem_wdata_r = {24'b0, ex_mem_store_data[7:0]}; end
                    2'b01: begin dmem_be_r = 4'b0010; dmem_wdata_r = {16'b0, ex_mem_store_data[7:0], 8'b0}; end
                    2'b10: begin dmem_be_r = 4'b0100; dmem_wdata_r = {8'b0, ex_mem_store_data[7:0], 16'b0}; end
                    2'b11: begin dmem_be_r = 4'b1000; dmem_wdata_r = {ex_mem_store_data[7:0], 24'b0}; end
                endcase
            end
            default: begin // SW
                dmem_be_r    = 4'b1111;
                dmem_wdata_r = ex_mem_store_data;
            end
        endcase
    end
    assign dmem_be    = dmem_be_r;
    assign dmem_wdata = dmem_wdata_r;

    // dmem is also synchronous-read (BRAM-inferring): dmem_rdata reflects
    // dmem[dmem_addr] one cycle after the address is presented -- i.e. it
    // isn't valid until the WB-stage cycle for this load, not MEM. So the
    // byte/halfword extraction moves to the WB section below; all this
    // stage does is carry funct3/byte_offset forward so WB can still
    // interpret the (later-arriving) data correctly.

    // QDOT4/QDOT8 add-tree + accumulate stage (MEM half of the pipelined
    // unit): wide=1 (QDOT8) sums all 8 lanes, wide=0 (QDOT4) sums only the
    // low 4.
    wire [31:0] qdot_result_mem;
    qdot_add QDOT_ADD (
        .p0(ex_mem_p0), .p1(ex_mem_p1), .p2(ex_mem_p2), .p3(ex_mem_p3),
        .p4(ex_mem_p4), .p5(ex_mem_p5), .p6(ex_mem_p6), .p7(ex_mem_p7),
        .wide(ex_mem_is_qdot8),
        .acc_in(ex_mem_qdot_acc_in), .acc_out(qdot_result_mem)
    );

    // ---------------- MEM/WB pipeline register ----------------
    always @(posedge clk) begin
        if (rst) begin
            mem_wb_reg_we  <= 1'b0;
            mem_wb_rd_addr <= 5'd0;
        end else begin
            mem_wb_pc           <= ex_mem_pc;
            mem_wb_alu_result   <= ex_mem_alu_result;
            mem_wb_qdot_result  <= qdot_result_mem;
            mem_wb_rd_addr      <= ex_mem_rd_addr;
            mem_wb_reg_we       <= ex_mem_reg_we;
            mem_wb_wb_sel       <= ex_mem_wb_sel;
            mem_wb_funct3       <= ex_mem_funct3;
            mem_wb_byte_offset  <= mem_byte_offset;
        end
    end

    // =====================================================================
    // WB stage
    // =====================================================================
    // dmem_rdata (BRAM's registered output) becomes valid exactly here, one
    // cycle after the address was presented in MEM -- so the load's
    // byte/halfword extraction happens now, using funct3/byte_offset
    // carried forward through the MEM/WB register above.
    reg [7:0]  wb_load_byte;
    reg [15:0] wb_load_half;
    always @(*) begin
        case (mem_wb_byte_offset)
            2'b00: wb_load_byte = dmem_rdata[7:0];
            2'b01: wb_load_byte = dmem_rdata[15:8];
            2'b10: wb_load_byte = dmem_rdata[23:16];
            2'b11: wb_load_byte = dmem_rdata[31:24];
        endcase
        wb_load_half = mem_wb_byte_offset[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];
    end

    reg [31:0] wb_load_data;
    always @(*) begin
        case (mem_wb_funct3)
            3'b000: wb_load_data = {{24{wb_load_byte[7]}},  wb_load_byte};  // LB
            3'b001: wb_load_data = {{16{wb_load_half[15]}}, wb_load_half}; // LH
            3'b010: wb_load_data = dmem_rdata;                              // LW
            3'b100: wb_load_data = {24'b0, wb_load_byte};                   // LBU
            3'b101: wb_load_data = {16'b0, wb_load_half};                   // LHU
            default: wb_load_data = dmem_rdata;
        endcase
    end

    always @(*) begin
        case (mem_wb_wb_sel)
            WB_ALU:  wb_wr_data = mem_wb_alu_result;
            WB_MEM:  wb_wr_data = wb_load_data;
            WB_QDOT: wb_wr_data = mem_wb_qdot_result;
            WB_PC4:  wb_wr_data = mem_wb_pc + 32'd4;
            default: wb_wr_data = 32'd0;
        endcase
    end

endmodule
