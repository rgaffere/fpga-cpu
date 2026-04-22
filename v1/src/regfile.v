`timescale 1ns / 1ps
`include "defines.vh"

module regfile (
    input  wire                     clk,
    input  wire                     rst,

    // Read port A
    input  wire [`REG_ADDR_W-1:0]   rs1_addr,
    output wire [`XLEN-1:0]         rs1_data,

    // Read port B
    input  wire [`REG_ADDR_W-1:0]   rs2_addr,
    output wire [`XLEN-1:0]         rs2_data,

    // Write port
    input  wire                     rd_we,
    input  wire [`REG_ADDR_W-1:0]   rd_addr,
    input  wire [`XLEN-1:0]         rd_data,
    
    // Passive debug taps, looks super gross i know. im gonna fix this later
    output wire [`XLEN-1:0]         dbg_r0,
    output wire [`XLEN-1:0]         dbg_r1,
    output wire [`XLEN-1:0]         dbg_r2,
    output wire [`XLEN-1:0]         dbg_r3,
    output wire [`XLEN-1:0]         dbg_r4,
    output wire [`XLEN-1:0]         dbg_r5,
    output wire [`XLEN-1:0]         dbg_r6,
    output wire [`XLEN-1:0]         dbg_r7,
    output wire [`XLEN-1:0]         dbg_r8,
    output wire [`XLEN-1:0]         dbg_r9,
    output wire [`XLEN-1:0]         dbg_r10,
    output wire [`XLEN-1:0]         dbg_r11,
    output wire [`XLEN-1:0]         dbg_r12,
    output wire [`XLEN-1:0]         dbg_r13,
    output wire [`XLEN-1:0]         dbg_r14,
    output wire [`XLEN-1:0]         dbg_r15,
    output wire [`XLEN-1:0]         dbg_r16,
    output wire [`XLEN-1:0]         dbg_r17,
    output wire [`XLEN-1:0]         dbg_r18,
    output wire [`XLEN-1:0]         dbg_r19,
    output wire [`XLEN-1:0]         dbg_r20,
    output wire [`XLEN-1:0]         dbg_r21,
    output wire [`XLEN-1:0]         dbg_r22,
    output wire [`XLEN-1:0]         dbg_r23,
    output wire [`XLEN-1:0]         dbg_r24,
    output wire [`XLEN-1:0]         dbg_r25,
    output wire [`XLEN-1:0]         dbg_r26,
    output wire [`XLEN-1:0]         dbg_r27,
    output wire [`XLEN-1:0]         dbg_r28,
    output wire [`XLEN-1:0]         dbg_r29,
    output wire [`XLEN-1:0]         dbg_r30,
    output wire [`XLEN-1:0]         dbg_r31
);

    reg [`XLEN-1:0] regs [0:`REG_COUNT-1];
    integer i;

    // ------------------------------------------------------------
    // Synchronous write / reset
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < `REG_COUNT; i = i + 1)
                regs[i] <= {`XLEN{1'b0}};
        end else begin
            if (rd_we && (rd_addr != `REG_ZERO))
                regs[rd_addr] <= rd_data;

            // Keep r0 pinned to zero no matter what
            regs[`REG_ZERO] <= {`XLEN{1'b0}};
        end
    end

    // ------------------------------------------------------------
    // Combinational reads
    // ------------------------------------------------------------
    assign rs1_data = regs[rs1_addr];
    assign rs2_data = regs[rs2_addr];

    assign dbg_r0  = regs[0];
    assign dbg_r1  = regs[1];
    assign dbg_r2  = regs[2];
    assign dbg_r3  = regs[3];
    assign dbg_r4  = regs[4];
    assign dbg_r5  = regs[5];
    assign dbg_r6  = regs[6];
    assign dbg_r7  = regs[7];
    assign dbg_r8  = regs[8];
    assign dbg_r9  = regs[9];
    assign dbg_r10 = regs[10];
    assign dbg_r11 = regs[11];
    assign dbg_r12 = regs[12];
    assign dbg_r13 = regs[13];
    assign dbg_r14 = regs[14];
    assign dbg_r15 = regs[15];
    assign dbg_r16 = regs[16];
    assign dbg_r17 = regs[17];
    assign dbg_r18 = regs[18];
    assign dbg_r19 = regs[19];
    assign dbg_r20 = regs[20];
    assign dbg_r21 = regs[21];
    assign dbg_r22 = regs[22];
    assign dbg_r23 = regs[23];
    assign dbg_r24 = regs[24];
    assign dbg_r25 = regs[25];
    assign dbg_r26 = regs[26];
    assign dbg_r27 = regs[27];
    assign dbg_r28 = regs[28];
    assign dbg_r29 = regs[29];
    assign dbg_r30 = regs[30];
    assign dbg_r31 = regs[31];

endmodule