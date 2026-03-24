`timescale 1ns / 1ps
`include "defines.vh"

module mem_subsystem #(
    parameter MEM_BYTES = 65536,
    parameter INIT_FILE = ""
)(
    input  wire                     clk,
    input  wire                     rst,

    // ============================================================
    // Instruction fetch side
    // ============================================================
    input  wire                     if_req,
    input  wire [`XLEN-1:0]         if_addr,
    output reg  [`XLEN-1:0]         if_rdata,
    output reg                      if_ready,
    output reg                      if_fault,
    output reg                      if_misaligned,

    // ============================================================
    // Data side
    // ============================================================
    input  wire                     d_req,
    input  wire                     d_we,
    input  wire [`MEM_SIZE_W-1:0]   d_size,
    input  wire [`XLEN-1:0]         d_addr,
    input  wire [`XLEN-1:0]         d_wdata,
    output reg  [`XLEN-1:0]         d_rdata,
    output reg                      d_ready,
    output reg                      d_fault,
    output reg                      d_misaligned
);

    // ------------------------------------------------------------
    // Local wires into BRAM
    // ------------------------------------------------------------
    reg                      bram_if_req;
    reg  [`XLEN-1:0]         bram_if_addr;
    wire [`XLEN-1:0]         bram_if_rdata;

    reg                      bram_d_req;
    reg                      bram_d_we;
    reg  [`MEM_SIZE_W-1:0]   bram_d_size;
    reg  [`XLEN-1:0]         bram_d_addr;
    reg  [`XLEN-1:0]         bram_d_wdata;
    wire [`XLEN-1:0]         bram_d_rdata;

    // ------------------------------------------------------------
    // Address translation / validity
    // ------------------------------------------------------------
    function automatic is_low_window;
        input [`XLEN-1:0] addr;
        begin
            is_low_window = (addr < MEM_BYTES);
        end
    endfunction

    function automatic is_vec_window;
        input [`XLEN-1:0] addr;
        begin
            is_vec_window = (addr >= `RESET_PC) &&
                            ((addr - `RESET_PC) < MEM_BYTES);
        end
    endfunction

    function automatic addr_valid;
        input [`XLEN-1:0] addr;
        input [`MEM_SIZE_W-1:0] size;
        reg [`XLEN-1:0] last_addr;
        begin
            case (size)
                `MEM_SIZE_B:  last_addr = addr;
                `MEM_SIZE_H:  last_addr = addr + 32'd1;
                `MEM_SIZE_WD: last_addr = addr + 32'd3;
                default:      last_addr = addr;
            endcase

            addr_valid =
                ((is_low_window(addr) && is_low_window(last_addr)) ||
                 (is_vec_window(addr) && is_vec_window(last_addr)));
        end
    endfunction

    function automatic [`XLEN-1:0] translate_addr;
        input [`XLEN-1:0] addr;
        begin
            if (is_vec_window(addr))
                translate_addr = addr - `RESET_PC;
            else
                translate_addr = addr;
        end
    endfunction

    // ------------------------------------------------------------
    // Alignment checks
    // ------------------------------------------------------------
    wire if_align_fault = (if_addr[1:0] != 2'b00);

    wire d_align_fault =
        (d_size == `MEM_SIZE_B)  ? 1'b0 :
        (d_size == `MEM_SIZE_H)  ? d_addr[0] :
        (d_size == `MEM_SIZE_WD) ? (d_addr[1:0] != 2'b00) :
                                   1'b1;

    wire if_access_fault = !addr_valid(if_addr, `MEM_SIZE_WD);
    wire d_access_fault  = !addr_valid(d_addr, d_size);

    // ------------------------------------------------------------
    // One outstanding response per side
    // ------------------------------------------------------------
    reg if_pending;
    reg d_pending;

    reg if_pending_fault;
    reg d_pending_fault;

    reg if_pending_misaligned;
    reg d_pending_misaligned;

    // One-cycle cooldown: prevent re-acceptance on the same cycle
    // that a response fires (pending clears to 0 but req is still
    // asserted from the previous state).
    reg if_just_responded;
    reg d_just_responded;

    // ------------------------------------------------------------
    // Arbitration
    // ------------------------------------------------------------
    wire d_new_req  = d_req  && !d_pending  && !d_just_responded;
    wire if_new_req = if_req && !if_pending && !if_just_responded;

    wire d_accept  = d_new_req;
    wire if_accept = if_new_req && !d_new_req;

    // ------------------------------------------------------------
    // BRAM instance
    // ------------------------------------------------------------
    mem_bram #(
        .MEM_BYTES(MEM_BYTES),
        .INIT_FILE(INIT_FILE)
    ) u_mem_bram (
        .clk      (clk),
        .rst      (rst),

        .if_req   (bram_if_req),
        .if_addr  (bram_if_addr),
        .if_rdata (bram_if_rdata),

        .d_req    (bram_d_req),
        .d_we     (bram_d_we),
        .d_size   (bram_d_size),
        .d_addr   (bram_d_addr),
        .d_wdata  (bram_d_wdata),
        .d_rdata  (bram_d_rdata)
    );

    // ------------------------------------------------------------
    // Drive BRAM only on acceptance of a new valid request
    // ------------------------------------------------------------
    always @(*) begin
        bram_if_req   = 1'b0;
        bram_if_addr  = {`XLEN{1'b0}};

        bram_d_req    = 1'b0;
        bram_d_we     = 1'b0;
        bram_d_size   = `MEM_SIZE_WD;
        bram_d_addr   = {`XLEN{1'b0}};
        bram_d_wdata  = {`XLEN{1'b0}};

        if (if_accept && !if_align_fault && !if_access_fault) begin
            bram_if_req  = 1'b1;
            bram_if_addr = translate_addr(if_addr);
        end

        if (d_accept && !d_align_fault && !d_access_fault) begin
            bram_d_req   = 1'b1;
            bram_d_we    = d_we;
            bram_d_size  = d_size;
            bram_d_addr  = translate_addr(d_addr);
            bram_d_wdata = d_wdata;
        end
    end

    // ------------------------------------------------------------
    // Response generation
    // Every accepted request completes on the next cycle, either
    // with ready or fault.
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            if_rdata              <= {`XLEN{1'b0}};
            if_ready              <= 1'b0;
            if_fault              <= 1'b0;
            if_misaligned         <= 1'b0;

            d_rdata               <= {`XLEN{1'b0}};
            d_ready               <= 1'b0;
            d_fault               <= 1'b0;
            d_misaligned          <= 1'b0;

            if_pending            <= 1'b0;
            d_pending             <= 1'b0;
            if_pending_fault      <= 1'b0;
            d_pending_fault       <= 1'b0;
            if_pending_misaligned <= 1'b0;
            d_pending_misaligned  <= 1'b0;

            if_just_responded     <= 1'b0;
            d_just_responded      <= 1'b0;
        end else begin
            // pulse outputs
            if_ready      <= 1'b0;
            if_fault      <= 1'b0;
            if_misaligned <= 1'b0;

            d_ready       <= 1'b0;
            d_fault       <= 1'b0;
            d_misaligned  <= 1'b0;

            // Cooldown flags: pulse for one cycle after response
            if_just_responded <= 1'b0;
            d_just_responded  <= 1'b0;

            // -------------------------
            // Complete prior IF request
            // -------------------------
            if (if_pending) begin
                if_pending        <= 1'b0;
                if_just_responded <= 1'b1;

                if (if_pending_fault) begin
                    if_fault      <= 1'b1;
                    if_misaligned <= if_pending_misaligned;
                end else begin
                    if_rdata <= bram_if_rdata;
                    if_ready <= 1'b1;
                end
            end

            // -------------------------
            // Complete prior DATA request
            // -------------------------
            if (d_pending) begin
                d_pending        <= 1'b0;
                d_just_responded <= 1'b1;

                if (d_pending_fault) begin
                    d_fault      <= 1'b1;
                    d_misaligned <= d_pending_misaligned;
                end else begin
                    d_rdata <= bram_d_rdata;
                    d_ready <= 1'b1;
                end
            end

            // -------------------------
            // Accept new IF request
            // -------------------------
            if (if_accept) begin
                if_pending            <= 1'b1;
                if_pending_fault      <= if_align_fault || if_access_fault;
                if_pending_misaligned <= if_align_fault;
            end

            // -------------------------
            // Accept new DATA request
            // -------------------------
            if (d_accept) begin
                d_pending           <= 1'b1;
                d_pending_fault     <= d_align_fault || d_access_fault;
                d_pending_misaligned<= d_align_fault;
            end
        end
    end

endmodule