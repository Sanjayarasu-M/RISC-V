// top.v -- wraps cpu_core with BRAM-inferring instr/data memories.
//
// Both reads are synchronous (registered output) -- the standard Xilinx
// template Vivado recognizes and maps to Block RAM instead of distributed
// RAM/registers. That 1-cycle read latency is exactly what cpu_core.v's IF
// and WB stages are built around (see the comments there): pc/dmem_addr are
// themselves registers, so re-presenting the same address during a stall
// naturally re-reads the same data with no extra logic needed.
//
// $readmemh-based init (below) is a simulation convenience that Vivado also
// honors for BRAM initial contents at synthesis time -- no separate board
// bring-up flow needed to get program/data into memory for this project.
//
// imem_data_r's update is gated by imem_stall (asserted during a hazard
// stall): pc leads the IF/ID register by two cycles here (BRAM latency +
// the buffer register), so a stall detected once the conflicting
// instruction reaches ID would otherwise let this register overwrite an
// already-in-flight, not-yet-consumed fetch before it's ever read. See the
// IF stage comment in cpu_core.v.
module top #(
    parameter MEM_WORDS = 1024,
    parameter IMEM_FILE = "program.hex",
    parameter DMEM_FILE = ""            // optional: preloads .data/.rodata (real toolchain builds)
)(
    input wire clk,
    input wire rst
);
    wire [31:0] imem_addr, imem_data;
    wire        imem_stall;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire        dmem_we;
    wire [3:0]  dmem_be;

    // rom_style="block": imem has no write port (see fpga_top.v for why
    // that matters to Vivado's memory inference); harmless for Icarus, but
    // keeps this module correct too if it's ever synthesized directly.
    (* rom_style = "block" *) reg [31:0] imem [0:MEM_WORDS-1];
    reg [31:0] dmem [0:MEM_WORDS-1];

    initial begin
        $readmemh(IMEM_FILE, imem);
        if (DMEM_FILE != "")
            $readmemh(DMEM_FILE, dmem);
    end

    reg [31:0] imem_data_r;
    always @(posedge clk) begin
        if (!imem_stall)
            imem_data_r <= imem[imem_addr[31:2]];
    end
    assign imem_data = imem_data_r;

    reg [31:0] dmem_rdata_r;
    always @(posedge clk) begin
        if (dmem_we) begin
            if (dmem_be[0]) dmem[dmem_addr[31:2]][7:0]   <= dmem_wdata[7:0];
            if (dmem_be[1]) dmem[dmem_addr[31:2]][15:8]  <= dmem_wdata[15:8];
            if (dmem_be[2]) dmem[dmem_addr[31:2]][23:16] <= dmem_wdata[23:16];
            if (dmem_be[3]) dmem[dmem_addr[31:2]][31:24] <= dmem_wdata[31:24];
        end
        dmem_rdata_r <= dmem[dmem_addr[31:2]];
    end
    assign dmem_rdata = dmem_rdata_r;

    cpu_core CORE (
        .clk(clk), .rst(rst),
        .imem_addr(imem_addr), .imem_data(imem_data), .imem_stall(imem_stall),
        .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_we(dmem_we),
        .dmem_be(dmem_be), .dmem_rdata(dmem_rdata)
    );
endmodule
