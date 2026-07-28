// fpga_top.v -- FPGA-deployment top level: CPU + BRAM memories + UART TX.
//
// Kept separate from top.v (which stays the simulation-focused CPU+memory
// wrapper used by all the Phase 1-3 testbenches) since this one adds a UART
// peripheral that needs direct access to the data-memory bus to snoop
// writes -- top.v's clean 2-port interface has no way to expose that
// without disturbing every existing testbench.
//
// UART "peripheral": writing a byte to UART_TX_ADDR transmits it. This is
// not a real bus (one fixed address, no backpressure/ready readback to the
// CPU) -- firmware must space writes apart in software (e.g. a delay loop)
// to avoid overrunning the transmitter. Good enough to demonstrate the
// mechanism; a real design would want a proper memory-mapped peripheral
// bus with a readable status register.
module fpga_top #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter BAUD        = 115200,
    parameter MEM_WORDS   = 1024,
    parameter IMEM_FILE   = "program.hex",
    parameter DMEM_FILE   = ""
)(
    input  wire clk,
    input  wire rst,
    output wire uart_tx_pin
);
    localparam UART_TX_ADDR = 32'h000007F0;

    wire [31:0] imem_addr, imem_data;
    wire        imem_stall;
    wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
    wire        dmem_we;
    wire [3:0]  dmem_be;

    // imem has no write port anywhere (populated only by $readmemh at init),
    // so Vivado sees a pure ROM and its default heuristic can pick
    // LUT-based combinational logic over Block RAM for it (confirmed by a
    // synthesis run: dmem correctly mapped to a RAMB36E2, but imem never
    // appeared in either the Block RAM or Distributed RAM mapping reports
    // at all -- it had been folded into ~1900 LUTs of decode logic
    // instead). rom_style="block" forces the intended BRAM mapping.
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

    // ---------------- UART TX "peripheral" ----------------
    reg [7:0] uart_data;
    reg       uart_valid;
    wire      uart_ready;

    always @(posedge clk) begin
        if (rst) begin
            uart_valid <= 1'b0;
        end else begin
            uart_valid <= 1'b0;
            if (dmem_we && dmem_addr == UART_TX_ADDR) begin
                uart_data  <= dmem_wdata[7:0];
                uart_valid <= 1'b1;
            end
        end
    end

    uart_tx #(.CLK_FREQ_HZ(CLK_FREQ_HZ), .BAUD(BAUD)) UART_TX_INST (
        .clk(clk), .rst(rst),
        .data(uart_data), .valid(uart_valid), .ready(uart_ready),
        .tx(uart_tx_pin)
    );
endmodule
