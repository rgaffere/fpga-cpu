`timescale 1ns / 1ps
`include "defines.vh"

module trap_regs (
    input  wire                     clk,
    input  wire                     rst,
    input  wire                     trap_enter,
    input  wire [`TRAP_CAUSE_W-1:0] trap_cause,
    input  wire [`XLEN-1:0]         pc_in,
    input  wire                     eret,
    input  wire                     ext_irq,
    output reg  [`XLEN-1:0]         epc_out,
    output reg  [`XLEN-1:0]         cause_out,
    output reg  [`XLEN-1:0]         status_out
);

    wire irq_pending = ext_irq & status_out[`STATUS_IE];

    always @(posedge clk) begin
        if (rst) begin
            epc_out    <= {`XLEN{1'b0}};
            cause_out  <= {`XLEN{1'b0}};
            status_out <= {`XLEN{1'b0}};
        end else if (trap_enter) begin
            epc_out                   <= pc_in;
            cause_out                 <= trap_cause;
            status_out[`STATUS_PIE]   <= status_out[`STATUS_IE];
            status_out[`STATUS_IE]    <= 1'b0;
        end else if (eret) begin
            status_out[`STATUS_IE]    <= status_out[`STATUS_PIE];
            status_out[`STATUS_PIE]   <= 1'b0;
        end
    end

endmodule