`timescale 1ns / 1ps
`include "defines.vh"

module pc (
    input  wire                 clk,
    input  wire                 rst,
    input  wire                 pc_we,
    input  wire [`XLEN-1:0]     next_pc,
    output reg  [`XLEN-1:0]     pc
);

    always @(posedge clk) begin
        if (rst)
            pc <= `RESET_PC;
        else if (pc_we)
            pc <= next_pc;
    end

endmodule