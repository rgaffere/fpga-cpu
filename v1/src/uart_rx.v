module uart_rx #(
    parameter integer CLKS_PER_BIT = 868
)(
    input  wire clk,
    input  wire rst,
    input  wire rx_serial,
    input  wire rx_clear,
    output reg  [7:0] rx_data,
    output reg rx_valid
);

    // FSM states
    localparam IDLE = 2'd0;
    localparam START = 2'd1;
    localparam DATA = 2'd2;
    localparam STOP = 2'd3;

    // Half-period offset used to center-sample each bit
    localparam HALF_BIT = CLKS_PER_BIT / 2;

    reg [1:0] state;
    reg [15:0] baud_cnt;
    reg [2:0] bit_idx;
    reg [7:0] rx_shift;

    // Two-flop synchronizer - async input crosses into clk domain cleanly
    reg rx_sync_0, rx_sync_1;
    always @(posedge clk) begin
        rx_sync_0 <= rx_serial;
        rx_sync_1 <= rx_sync_0;
    end

    // Convenience alias for the synchronized, stable rx line
    wire rx = rx_sync_1;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            baud_cnt <= 0;
            bit_idx <= 0;
            rx_shift <= 8'h00;
            rx_data <= 8'h00;
            rx_valid <= 1'b0;
        end else begin

            // rx_valid stays asserted until the caller clears it
            if (rx_clear)
                rx_valid <= 1'b0;

            case (state)

                IDLE: begin
                    baud_cnt <= 0;
                    bit_idx <= 0;

                    // Falling edge on rx_serial = start bit detected
                    if (!rx)
                        state <= START;
                end

                // Wait half a bit period so subsequent samples land in the
                // center of each data bit rather than at the edge.
                START: begin
                    if (baud_cnt == HALF_BIT - 1) begin
                        baud_cnt <= 0;

                        // Confirm start bit still low — not just a glitch
                        if (!rx)
                            state <= DATA;
                        else
                            state <= IDLE;  // glitch — abort and re-arm
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // Sample once per full bit period, LSB first
                DATA: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 0;
                        rx_shift[bit_idx] <= rx;   // capture center sample

                        if (bit_idx == 3'd7) begin
                            bit_idx <= 0;
                            state <= STOP;
                        end else begin
                            bit_idx <= bit_idx + 1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                // Sample the stop bit; only commit the byte if it is valid (high)
                STOP: begin
                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 0;
                        state <= IDLE;

                        if (rx) begin           // valid stop bit
                            rx_data <= rx_shift;
                            rx_valid <= 1'b1;
                        end
                        // If stop bit is low (framing error) the byte is
                        // silently discarded and we return to IDLE to re-arm.
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule