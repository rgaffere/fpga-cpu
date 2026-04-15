module uart_tx #(
    parameter integer CLKS_PER_BIT = 868 // Desired UART: 115200 bits/sec
)(
    input wire clk,
    input wire rst,
    input wire tx_start,
    input wire [7:0] tx_data,
    output reg tx_serial,
    output reg tx_busy
);

    // FSM states
    localparam IDLE = 2'd0;
    localparam START = 2'd1;
    localparam DATA = 2'd2;
    localparam STOP = 2'd3;

    reg [1:0] state;
    reg [15:0] baud_cnt;
    reg [2:0] bit_idx;
    reg [7:0] tx_shift;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            baud_cnt <= 0;
            bit_idx <= 0;
            tx_shift <= 8'h00;
            tx_serial <= 1'b1;   // idle line high
            tx_busy <= 1'b0;
        end else begin
            case (state)

                IDLE: begin
                    tx_serial <= 1'b1;
                    tx_busy <= 1'b0;
                    baud_cnt <= 0;
                    bit_idx <= 0;

                    if (tx_start) begin
                        tx_shift <= tx_data;
                        tx_busy <= 1'b1;
                        state <= START;
                    end
                end

                START: begin
                    tx_serial <= 1'b0; // start bit — pull low

                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 0;
                        state <= DATA;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                DATA: begin
                    tx_serial <= tx_shift[bit_idx]; // LSB first

                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 0;

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

                STOP: begin
                    tx_serial <= 1'b1; // stop bit — pull high

                    if (baud_cnt == CLKS_PER_BIT - 1) begin
                        baud_cnt <= 0;
                        state <= IDLE;
                    end else begin
                        baud_cnt <= baud_cnt + 1;
                    end
                end

                default: state <= IDLE;

            endcase
        end
    end

endmodule