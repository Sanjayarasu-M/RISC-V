// uart_rx.v -- simple 8N1 UART receiver. Provided as a tested, synthesizable
// building block for a future UART bootloader; this project doesn't build
// the bootloader protocol itself (nothing to validate it against without
// real hardware).
//
// bit_idx tracks which period is currently elapsing: 0 = start bit,
// 1..8 = data bits 0..7 (LSB first), 9 = stop bit, after which the byte is
// finalized. Each data bit is sampled at the MIDDLE of its period
// (baud_cnt==DIV/2), not at the boundary -- sampling right at a period
// boundary is fragile against the 2-cycle input synchronizer delay, which
// is enough to shift the sample into the next bit's window and corrupt
// every bit position by one (caught by tb_uart.v's loopback test).
module uart_rx #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter BAUD        = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid   // pulses high for 1 cycle when a byte is received
);
    localparam integer DIV      = CLK_FREQ_HZ / BAUD;
    localparam integer HALF_DIV = DIV / 2;

    reg rx_sync0, rx_sync1;
    always @(posedge clk) begin
        rx_sync0 <= rx;
        rx_sync1 <= rx_sync0;
    end

    reg [$clog2(DIV+1)-1:0] baud_cnt;
    reg [3:0] bit_idx;
    reg [7:0] shift_reg;
    reg       busy;

    always @(posedge clk) begin
        if (rst) begin
            busy     <= 1'b0;
            valid    <= 1'b0;
            baud_cnt <= 0;
            bit_idx  <= 0;
        end else begin
            valid <= 1'b0;
            if (!busy) begin
                if (rx_sync1 == 1'b0) begin // start bit edge detected
                    busy     <= 1'b1;
                    baud_cnt <= 0;
                    bit_idx  <= 0;
                end
            end else begin
                baud_cnt <= (baud_cnt == DIV - 1) ? 0 : baud_cnt + 1'b1;

                if (baud_cnt == HALF_DIV && bit_idx >= 1 && bit_idx <= 8)
                    shift_reg <= {rx_sync1, shift_reg[7:1]};

                if (baud_cnt == DIV - 1) begin
                    if (bit_idx == 9) begin
                        busy  <= 1'b0;
                        data  <= shift_reg;
                        valid <= 1'b1;
                    end else begin
                        bit_idx <= bit_idx + 1'b1;
                    end
                end
            end
        end
    end
endmodule
