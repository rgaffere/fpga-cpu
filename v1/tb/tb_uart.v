`timescale 1ns / 1ps

module tb_uart;

    localparam integer CLKS_PER_BIT = 868;
    localparam real CLK_PERIOD = 10.0;

    reg clk = 0;
    reg rst = 1;

    reg tx_start = 0;
    reg [7:0] tx_data = 8'h00;
    wire tx_serial;
    wire tx_busy;

    reg rx_clear = 0;
    wire [7:0] rx_data;
    wire rx_valid;

    // Loopback: TX feeds RX directly
    wire rx_serial = tx_serial;

    uart_tx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) dut_tx (
        .clk(clk),
        .rst(rst),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_serial(tx_serial),
        .tx_busy(tx_busy)
    );

    uart_rx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) dut_rx (
        .clk(clk),
        .rst(rst),
        .rx_serial(rx_serial),
        .rx_clear(rx_clear),
        .rx_data(rx_data),
        .rx_valid(rx_valid)
    );

    // 100 MHz clock
    always #(CLK_PERIOD/2) clk = ~clk;

    task send_byte(input [7:0] data);
    begin
        @(posedge clk);
        tx_data  <= data;
        tx_start <= 1'b1;
        @(posedge clk);
        tx_start <= 1'b0;
    end
    endtask

    task clear_rx_valid;
    begin
        @(posedge clk);
        rx_clear <= 1'b1;
        @(posedge clk);
        rx_clear <= 1'b0;
    end
    endtask

    initial begin
        $dumpfile("uart_tb.vcd");
        $dumpvars(0, tb_uart);

        // Reset
        repeat (5) @(posedge clk);
        rst <= 0;

        // Test 1: send 0xA5
        send_byte(8'hA5);
        wait (rx_valid == 1'b1);

        if (rx_data == 8'hA5)
            $display("PASS: received 0xA5");
        else
            $display("FAIL: expected 0xA5, got %h", rx_data);

        clear_rx_valid;

        // Test 2: send 0x3C
        wait (tx_busy == 1'b0);
        send_byte(8'h3C);
        wait (rx_valid == 1'b1);

        if (rx_data == 8'h3C)
            $display("PASS: received 0x3C");
        else
            $display("FAIL: expected 0x3C, got %h", rx_data);

        clear_rx_valid;

        $display("Done.");
        #100;
        $finish;
    end

endmodule