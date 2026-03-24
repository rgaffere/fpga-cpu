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
    input  wire [`XLEN-1:0]         rd_data
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

endmodule