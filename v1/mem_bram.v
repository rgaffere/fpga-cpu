`timescale 1ns / 1ps
`include "defines.vh"

module mem_bram #(
    parameter MEM_BYTES = 65536,          // 64 KiB for bring-up/sim
    parameter INIT_FILE = ""
)(
    input  wire                 clk,
    input  wire                 rst,

    // -----------------------------
    // Instruction fetch port
    // -----------------------------
    input  wire                 if_req,
    input  wire [`XLEN-1:0]     if_addr,
    output reg  [`XLEN-1:0]     if_rdata,

    // -----------------------------
    // Data access port
    // -----------------------------
    input  wire                 d_req,
    input  wire                 d_we,
    input  wire [`MEM_SIZE_W-1:0] d_size,
    input  wire [`XLEN-1:0]     d_addr,
    input  wire [`XLEN-1:0]     d_wdata,
    output reg  [`XLEN-1:0]     d_rdata
);

    // Byte-addressable memory
    reg [7:0] mem [0:MEM_BYTES-1];
    integer i;

    // -----------------------------------------
    // Optional initialization
    // -----------------------------------------
    initial begin
        if (INIT_FILE != "") begin
            $readmemh(INIT_FILE, mem);
        end else begin
            for (i = 0; i < MEM_BYTES; i = i + 1)
                mem[i] = 8'h00;
        end
    end

    // -----------------------------------------
    // Synchronous reads and writes
    // -----------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            if_rdata <= {`XLEN{1'b0}};
            d_rdata  <= {`XLEN{1'b0}};
        end else begin
            // -----------------------------
            // Instruction fetch
            // Little-endian 32-bit assembly
            // -----------------------------
            if (if_req) begin
                if_rdata <= {
                    mem[if_addr + 32'd3],
                    mem[if_addr + 32'd2],
                    mem[if_addr + 32'd1],
                    mem[if_addr + 32'd0]
                };
            end

            // -----------------------------
            // Data read
            // -----------------------------
            if (d_req && !d_we) begin
                case (d_size)
                    `MEM_SIZE_B: begin
                        d_rdata <= {24'b0, mem[d_addr]};
                    end

                    `MEM_SIZE_H: begin
                        d_rdata <= {
                            16'b0,
                            mem[d_addr + 32'd1],
                            mem[d_addr + 32'd0]
                        };
                    end

                    `MEM_SIZE_WD: begin
                        d_rdata <= {
                            mem[d_addr + 32'd3],
                            mem[d_addr + 32'd2],
                            mem[d_addr + 32'd1],
                            mem[d_addr + 32'd0]
                        };
                    end

                    default: begin
                        d_rdata <= {`XLEN{1'b0}};
                    end
                endcase
            end

            // -----------------------------
            // Data write
            // -----------------------------
            if (d_req && d_we) begin
                case (d_size)
                    `MEM_SIZE_B: begin
                        mem[d_addr] <= d_wdata[7:0];
                    end

                    `MEM_SIZE_H: begin
                        mem[d_addr + 32'd0] <= d_wdata[7:0];
                        mem[d_addr + 32'd1] <= d_wdata[15:8];
                    end

                    `MEM_SIZE_WD: begin
                        mem[d_addr + 32'd0] <= d_wdata[7:0];
                        mem[d_addr + 32'd1] <= d_wdata[15:8];
                        mem[d_addr + 32'd2] <= d_wdata[23:16];
                        mem[d_addr + 32'd3] <= d_wdata[31:24];
                    end

                    default: begin
                        // no write
                    end
                endcase
            end
        end
    end

endmodule