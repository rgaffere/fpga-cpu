`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Ryan Gaffere
// 
// Create Date: 12/27/2025 01:54:53 AM
// Design Name:
// Module Name: pc
// Project Name: CPU v0
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

//I put this in its own file to keep things modular
module pc #(
    parameter PC_W = 16
)(
    input  wire             clk,
    input  wire             reset,
    input  wire             pc_we,
    input  wire [PC_W-1:0]  pc_next,
    output reg  [PC_W-1:0]  pc
);

    always @(posedge clk) begin
        if (reset)
            pc <= {PC_W{1'b0}};
        else if (pc_we)
            pc <= pc_next;
    end

endmodule

