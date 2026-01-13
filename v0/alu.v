`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Ryan Gaffere
// 
// Create Date: 12/24/2025 11:50:35 PM
// Design Name:
// Module Name: alu
// Project Name: CPU v0
// Target Devices: 
// Tool Versions: 
// Description: 8-bit ALU with registered outputs and NZCV flags. This is single cycle, NO MULTI-CYCLE OPS
//////////////////////////////////////////////////////////////////////////////////

module alu #(
    parameter WORD_W = 8,
    parameter OP_W   = 6,   // up to 64 operations

    // Flag bit positions (bitfield)
    parameter FLAG_N = 3,   // Negative
    parameter FLAG_Z = 2,   // Zero
    parameter FLAG_C = 1,   // Carry / No-borrow
    parameter FLAG_V = 0    // Signed overflow
) (
    input  wire [WORD_W-1:0] d_in0,
    input  wire [WORD_W-1:0] d_in1,
    input  wire              clk,
    input  wire [OP_W-1:0]   op_code,

    output reg  [WORD_W-1:0] d_out,
    output reg  [3:0]        flags
);

    // internal combinational results
    reg [WORD_W-1:0] res;
    reg carry;
    reg overflow;

    // signed views (for overflow detection)
    wire signed [WORD_W-1:0] s_a = d_in0;
    wire signed [WORD_W-1:0] s_b = d_in1;
    wire signed [WORD_W-1:0] s_r = res;

    // -------------------------
    // Combinational ALU
    // -------------------------
    always @(*) begin
        res      = {WORD_W{1'b0}};
        carry    = 1'b0;
        overflow = 1'b0;

        case (op_code)

            // Arithmetic
            6'd0: begin // ADD
                {carry, res} = d_in0 + d_in1;
                overflow = (~(s_a[WORD_W-1] ^ s_b[WORD_W-1])) &
                           ( s_a[WORD_W-1] ^ s_r[WORD_W-1]);
            end

            6'd1: begin // SUB
                {carry, res} = d_in0 - d_in1; // carry=1 means "no borrow" in this convention
                overflow = ( (s_a[WORD_W-1] ^ s_b[WORD_W-1])) &
                           ( s_a[WORD_W-1] ^ s_r[WORD_W-1]);
            end

            // Logical
            6'd2:  res = d_in0 & d_in1;        // AND
            6'd3:  res = d_in0 | d_in1;        // OR
            6'd4:  res = d_in0 ^ d_in1;        // XOR
            6'd5:  res = ~d_in0;               // NOT

            // Shifts
            6'd6:  res = d_in0 << d_in1[2:0];  // SHL
            6'd7:  res = d_in0 >> d_in1[2:0];  // SHR (logical)
            6'd8:  res = s_a >>> d_in1[2:0];   // SAR (arith)

            // Pass-through / utility
            6'd9:  res = d_in0;                // PASS A
            6'd10: res = d_in1;                // PASS B

            default: begin
                res      = {WORD_W{1'b0}};
                carry    = 1'b0;
                overflow = 1'b0;
            end
        endcase
    end

    // -------------------------
    // Registered outputs
    // -------------------------
    always @(posedge clk) begin
        d_out <= res;

        flags[FLAG_N] <= res[WORD_W-1];
        flags[FLAG_Z] <= (res == {WORD_W{1'b0}});
        flags[FLAG_C] <= carry;
        flags[FLAG_V] <= overflow;
    end

endmodule
