`timescale 1ns / 1ps
`include "defines.vh"

// ------------------------------------------------------------
// mem_bram — true dual-port BRAM wrapper
//
// Word-addressed 32-bit array. Vivado infers Block RAM cleanly
// from this pattern. Byte-offset arithmetic on a byte array
// (mem[addr+3] etc.) prevents BRAM inference — this avoids it.
//
// HEX FILE FORMAT: one 32-bit word per line, big-endian hex.
//   e.g. instruction 0x0480000a → one line: 0480000a
// Use convert_hex.py to convert from byte-format if needed.
// ------------------------------------------------------------

module mem_bram #(
    parameter MEM_BYTES = 65536,
    parameter INIT_FILE = "test_mem.hex"
)(
    input  wire                     clk,
    input  wire                     rst,

    // ----------------------------------------------------------
    // Instruction fetch port — byte address, must be word-aligned
    // ----------------------------------------------------------
    input  wire                     if_req,
    input  wire [`XLEN-1:0]         if_addr,
    output reg  [`XLEN-1:0]         if_rdata,

    // ----------------------------------------------------------
    // Data port — byte address, any alignment (checked upstream)
    // ----------------------------------------------------------
    input  wire                     d_req,
    input  wire                     d_we,
    input  wire [`MEM_SIZE_W-1:0]   d_size,
    input  wire [`XLEN-1:0]         d_addr,
    input  wire [`XLEN-1:0]         d_wdata,
    output wire [`XLEN-1:0]         d_rdata   // combinational after BRAM register
);

    localparam MEM_WORDS = MEM_BYTES / 4;
    localparam AW        = $clog2(MEM_WORDS);   // 14 for 64 KiB

    // ----------------------------------------------------------
    // 32-bit word-addressed BRAM
    // Vivado infers this as Block RAM with byte enables.
    // ----------------------------------------------------------
    (* ram_style = "block" *) reg [31:0] mem [0:MEM_WORDS-1];

    initial begin
        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    // ----------------------------------------------------------
    // Word addresses — drop bottom 2 bits
    // mem_subsystem has already translated the address
    // (reset vector window → 0-based offset) before calling us.
    // ----------------------------------------------------------
    wire [AW-1:0] if_waddr = if_addr[AW+1:2];
    wire [AW-1:0] d_waddr  = d_addr[AW+1:2];
    wire [1:0]    d_boff   = d_addr[1:0];      // byte offset within word

    // ----------------------------------------------------------
    // Byte-enable generation for writes
    // ----------------------------------------------------------
    reg [3:0] d_be;
    always @(*) begin
        case (d_size)
            `MEM_SIZE_B:  d_be = 4'b0001 << d_boff;
            `MEM_SIZE_H:  d_be = d_boff[1] ? 4'b1100 : 4'b0011;
            `MEM_SIZE_WD: d_be = 4'b1111;
            default:      d_be = 4'b0000;
        endcase
    end

    // ----------------------------------------------------------
    // Registered BRAM reads + latched extraction info
    // ----------------------------------------------------------
    reg [31:0]            d_rdata_raw;   // full word from BRAM
    reg [1:0]             d_boff_lat;    // byte offset at time of read
    reg [`MEM_SIZE_W-1:0] d_size_lat;   // access size at time of read

    always @(posedge clk) begin
        if (rst) begin
            if_rdata    <= {`XLEN{1'b0}};
            d_rdata_raw <= {`XLEN{1'b0}};
            d_boff_lat  <= 2'b0;
            d_size_lat  <= `MEM_SIZE_WD;
        end else begin

            // IF: always word-aligned, simple read
            if (if_req)
                if_rdata <= mem[if_waddr];

            // Data read: latch full word + address info
            if (d_req && !d_we) begin
                d_rdata_raw <= mem[d_waddr];
                d_boff_lat  <= d_boff;
                d_size_lat  <= d_size;
            end

            // Data write: byte-enable lanes
            // Vivado maps this to BRAM write-enable bits.
            if (d_req && d_we) begin
                if (d_be[0]) mem[d_waddr][ 7: 0] <= d_wdata[ 7: 0];
                if (d_be[1]) mem[d_waddr][15: 8] <= d_wdata[15: 8];
                if (d_be[2]) mem[d_waddr][23:16] <= d_wdata[23:16];
                if (d_be[3]) mem[d_waddr][31:24] <= d_wdata[31:24];
            end
        end
    end

    // ----------------------------------------------------------
    // Combinational byte/halfword extraction
    // d_rdata_raw and d_boff_lat are both stable one cycle after
    // the read request, so this mux resolves correctly when
    // mem_subsystem reads bram_d_rdata during response generation.
    // Sign/zero extension is still handled in datapath.v.
    // ----------------------------------------------------------
    reg [`XLEN-1:0] d_rdata_mux;

    always @(*) begin
        case (d_size_lat)
            `MEM_SIZE_B:  d_rdata_mux = {24'b0, d_rdata_raw[d_boff_lat*8 +: 8]};
            `MEM_SIZE_H:  d_rdata_mux = {16'b0, d_rdata_raw[d_boff_lat*8 +: 16]};
            `MEM_SIZE_WD: d_rdata_mux = d_rdata_raw;
            default:      d_rdata_mux = d_rdata_raw;
        endcase
    end

    assign d_rdata = d_rdata_mux;

endmodule