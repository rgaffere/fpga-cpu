`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Ryan
// 
// Create Date: 12/21/2025 01:03:27 PM
// Design Name: 
// Module Name: mm
// Project Name: CPU v0
// Target Devices: 
// Tool Versions: 
// Description: Memory module v1 for CPU project
//              Uses combi read/write. Async read, sync write
//              No fancy word module yet
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module mm #(
    parameter WORD_W = 8,
    parameter ADDR_W = 4
)(
    // write port
    input  [ADDR_W-1:0] waddr,
    input  [WORD_W-1:0] wdata,
    input               we,
    input               clk,

    // read port 0
    input  [ADDR_W-1:0] raddr0,
    output [WORD_W-1:0] rdata0,

    // read port 1
    input  [ADDR_W-1:0] raddr1,
    output [WORD_W-1:0] rdata1
);
    reg [WORD_W-1:0] mem [0:(1<<ADDR_W)-1];

    // synchronous write
    always @(posedge clk) begin
        if (we)
            mem[waddr] <= wdata;
    end

    // asynchronous reads (we use write-first to keep async read) also we include extra logic to make this deterministic
    assign rdata0 = (we && (waddr == raddr0)) ? wdata : mem[raddr0];
    assign rdata1 = (we && (waddr == raddr1)) ? wdata : mem[raddr1];

endmodule


