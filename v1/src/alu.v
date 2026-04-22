`timescale 1ns / 1ps
`include "defines.vh"

module alu (
    input  wire [`XLEN-1:0]     a,
    input  wire [`XLEN-1:0]     b,
    input  wire [`ALU_OP_W-1:0] alu_op,

    output reg  [`XLEN-1:0]     result,

    // Candidate flags from the current ALU operation.
    // Control logic decides whether to commit them.
    output reg                  flag_z,
    output reg                  flag_n,
    output reg                  flag_c,
    output reg                  flag_v
);

    reg [`XLEN:0] wide_sum;
    reg [`XLEN:0] wide_diff;

    always @(*) begin
        // Defaults
        result  = {`XLEN{1'b0}};
        flag_z  = 1'b0;
        flag_n  = 1'b0;
        flag_c  = 1'b0;
        flag_v  = 1'b0;
        wide_sum  = {(`XLEN+1){1'b0}};
        wide_diff = {(`XLEN+1){1'b0}};

        case (alu_op)
            `ALU_ADD: begin
                wide_sum = {1'b0, a} + {1'b0, b};
                result   = wide_sum[`XLEN-1:0];

                flag_z   = (result == {`XLEN{1'b0}});
                flag_n   = result[`XLEN-1];
                flag_c   = wide_sum[`XLEN];
                flag_v   = (~(a[`XLEN-1] ^ b[`XLEN-1])) &
                           (a[`XLEN-1] ^ result[`XLEN-1]);
            end

            `ALU_SUB: begin
                wide_diff = {1'b0, a} - {1'b0, b};
                result    = wide_diff[`XLEN-1:0];

                flag_z    = (result == {`XLEN{1'b0}});
                flag_n    = result[`XLEN-1];
                flag_c    = (a >= b);  // no borrow
                flag_v    = (a[`XLEN-1] ^ b[`XLEN-1]) &
                            (a[`XLEN-1] ^ result[`XLEN-1]);
            end

            `ALU_AND: begin
                result  = a & b;
                flag_z  = (result == {`XLEN{1'b0}});
                flag_n  = result[`XLEN-1];
                flag_c  = 1'b0;
                flag_v  = 1'b0;
            end

            `ALU_OR: begin
                result  = a | b;
                flag_z  = (result == {`XLEN{1'b0}});
                flag_n  = result[`XLEN-1];
                flag_c  = 1'b0;
                flag_v  = 1'b0;
            end

            `ALU_XOR: begin
                result  = a ^ b;
                flag_z  = (result == {`XLEN{1'b0}});
                flag_n  = result[`XLEN-1];
                flag_c  = 1'b0;
                flag_v  = 1'b0;
            end

            `ALU_SLL: begin
                result  = a << b[4:0];
                flag_z  = (result == {`XLEN{1'b0}});
                flag_n  = result[`XLEN-1];
                flag_c  = 1'b0;
                flag_v  = 1'b0;
            end

            `ALU_SRL: begin
                result  = a >> b[4:0];
                flag_z  = (result == {`XLEN{1'b0}});
                flag_n  = result[`XLEN-1];
                flag_c  = 1'b0;
                flag_v  = 1'b0;
            end

            `ALU_SRA: begin
                result  = $signed(a) >>> b[4:0];
                flag_z  = (result == {`XLEN{1'b0}});
                flag_n  = result[`XLEN-1];
                flag_c  = 1'b0;
                flag_v  = 1'b0;
            end

            `ALU_PASS_A: begin
                result  = a;
                flag_z  = (result == {`XLEN{1'b0}});
                flag_n  = result[`XLEN-1];
                flag_c  = 1'b0;
                flag_v  = 1'b0;
            end

            `ALU_PASS_B: begin
                result  = b;
                flag_z  = (result == {`XLEN{1'b0}});
                flag_n  = result[`XLEN-1];
                flag_c  = 1'b0;
                flag_v  = 1'b0;
            end

            `ALU_MUL: begin
                result  = a * b;
                flag_z  = (result == {`XLEN{1'b0}});
                flag_n  = result[`XLEN-1];
                flag_c  = 1'b0;
                flag_v  = 1'b0;
            end

            // CMP = subtraction for flags, no architectural writeback
            `ALU_CMP: begin
                wide_diff = {1'b0, a} - {1'b0, b};
                result    = wide_diff[`XLEN-1:0];

                flag_z    = (result == {`XLEN{1'b0}});
                flag_n    = result[`XLEN-1];
                flag_c    = (a >= b);  // no borrow
                flag_v    = (a[`XLEN-1] ^ b[`XLEN-1]) &
                            (a[`XLEN-1] ^ result[`XLEN-1]);
            end

            // TEST = bitwise AND for flags
            `ALU_TEST: begin
                result  = a & b;
                flag_z  = (result == {`XLEN{1'b0}});
                flag_n  = result[`XLEN-1];
                flag_c  = 1'b0;
                flag_v  = 1'b0;
            end

            default: begin
                result  = {`XLEN{1'b0}};
                flag_z  = 1'b1;
                flag_n  = 1'b0;
                flag_c  = 1'b0;
                flag_v  = 1'b0;
            end
        endcase
    end

endmodule