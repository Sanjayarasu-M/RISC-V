// uart_tx.v -- simple 8N1 UART transmitter.
module uart_tx #(
    parameter CLK_FREQ_HZ = 50_000_000,
    parameter BAUD        = 115200
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,
    input  wire       valid,   // pulse high for 1 cycle to start a transmit
    output reg        ready,   // high when idle and able to accept new data
    output reg        tx
);
    localparam integer DIV = CLK_FREQ_HZ / BAUD;

    reg [$clog2(DIV+1)-1:0] baud_cnt;
    reg [3:0]  bit_idx;     // 0=start, 1..8=data, 9=stop
    reg [9:0]  shift_reg;   // {stop, data[7:0], start}
    reg        busy;

    always @(posedge clk) begin
        if (rst) begin
            tx        <= 1'b1;
            busy      <= 1'b0;
            ready     <= 1'b1;
            baud_cnt  <= 0;
            bit_idx   <= 0;
            shift_reg <= 10'h3FF;
        end else if (!busy) begin
            ready <= 1'b1;
            if (valid) begin
                shift_reg <= {1'b1, data, 1'b0}; // stop bit, 8 data bits, start bit
                busy      <= 1'b1;
                ready     <= 1'b0;
                baud_cnt  <= 0;
                bit_idx   <= 0;
                tx        <= 1'b0; // drive start bit immediately
            end
        end else begin
            ready <= 1'b0;
            if (baud_cnt == DIV - 1) begin
                baud_cnt <= 0;
                if (bit_idx == 9) begin
                    busy <= 1'b0;
                    tx   <= 1'b1; // idle high after stop bit
                end else begin
                    shift_reg <= {1'b1, shift_reg[9:1]};
                    tx        <= shift_reg[1]; // next bit to send
                    bit_idx   <= bit_idx + 1'b1;
                end
            end else begin
                baud_cnt <= baud_cnt + 1'b1;
            end
        end
    end
endmodule
