`timescale 1ns / 1ps
`include "defines.vh"

// ============================================================
// RG Sonic32 v1 - Debug Module 
// Author: Ryan Gaffere
// File: debug.v
// ============================================================
// Purely passive observer. Watches CPU execution via tapped
// signals from cpu_top, captures reportable events into a 20-slot
// synchronous FIFO, and drains them over UART. On HALT the FSM
// drains any remaining FIFO entries first, then emits the full
// 32-register dump.
//
// Events captured:
//   WB    : (state == S_WRITEBACK) && rd_we
//   STORE : (state == S_MEM_WRITE) && d_ready && d_we
//   HALT  : halt || (state == S_HALT)  -> sets halt_pending;
//            FSM transitions to halt intro only after FIFO empty
//
// Control-flow events (BRANCH, JUMP) are not traced.
//
// FIFO: 20 entries x 166 bits. Events dropped silently when full.
// Simultaneous push+pop is handled correctly (count unchanged).
//
// Trace line formats (CR LF terminated):
//   WB    : "PC=XXXXXXXX IR=XXXXXXXX RD=XX WB=XXXXXXXX\r\n"      (43 bytes)
//   STORE : "PC=XXXXXXXX IR=XXXXXXXX ST A=XXXXXXXX D=XXXXXXXX\r\n" (50 bytes)
//   HALT  : "HALT\r\n" followed by 32 lines of "rNN=XXXXXXXX\r\n"
//
// FIFO entry layout [165:0]:
//   [165]     : event_type  (0=WB, 1=STORE)
//   [164:133] : pc          (32b)
//   [132:101] : instr       (32b)
//   [100:96]  : rd_idx      (5b)
//   [95:64]   : wb_data     (32b)
//   [63:32]   : alu_result  (32b)
//   [31:0]    : store_data  (32b)
// ============================================================

module debug #(
    parameter integer CLKS_PER_BIT = 868  // 115200 baud @ 100 MHz
)(
    input  wire clk,
    input  wire rst,

    // ------------------------------------------------------------
    // Instruction context
    // ------------------------------------------------------------
    input  wire [`XLEN-1:0] instr,
    input  wire [`XLEN-1:0] instr_pc,
    input  wire [`REG_ADDR_W-1:0] rd_idx,

    // ------------------------------------------------------------
    // Execution results
    // ------------------------------------------------------------
    input  wire [`XLEN-1:0] alu_result_out,
    input  wire [`XLEN-1:0] wb_data_out,
    input  wire [`XLEN-1:0] store_data_out,

    // ------------------------------------------------------------
    // Control / state
    // ------------------------------------------------------------
    input  wire [`FSM_STATE_W-1:0] state_out,
    input  wire rd_we,
    input  wire d_we,
    input  wire d_ready,
    input  wire halt,

    // ------------------------------------------------------------
    // Register taps (all 32 architectural registers)
    // ------------------------------------------------------------
    input  wire [`XLEN-1:0] dbg_r0,
    input  wire [`XLEN-1:0] dbg_r1,
    input  wire [`XLEN-1:0] dbg_r2,
    input  wire [`XLEN-1:0] dbg_r3,
    input  wire [`XLEN-1:0] dbg_r4,
    input  wire [`XLEN-1:0] dbg_r5,
    input  wire [`XLEN-1:0] dbg_r6,
    input  wire [`XLEN-1:0] dbg_r7,
    input  wire [`XLEN-1:0] dbg_r8,
    input  wire [`XLEN-1:0] dbg_r9,
    input  wire [`XLEN-1:0] dbg_r10,
    input  wire [`XLEN-1:0] dbg_r11,
    input  wire [`XLEN-1:0] dbg_r12,
    input  wire [`XLEN-1:0] dbg_r13,
    input  wire [`XLEN-1:0] dbg_r14,
    input  wire [`XLEN-1:0] dbg_r15,
    input  wire [`XLEN-1:0] dbg_r16,
    input  wire [`XLEN-1:0] dbg_r17,
    input  wire [`XLEN-1:0] dbg_r18,
    input  wire [`XLEN-1:0] dbg_r19,
    input  wire [`XLEN-1:0] dbg_r20,
    input  wire [`XLEN-1:0] dbg_r21,
    input  wire [`XLEN-1:0] dbg_r22,
    input  wire [`XLEN-1:0] dbg_r23,
    input  wire [`XLEN-1:0] dbg_r24,
    input  wire [`XLEN-1:0] dbg_r25,
    input  wire [`XLEN-1:0] dbg_r26,
    input  wire [`XLEN-1:0] dbg_r27,
    input  wire [`XLEN-1:0] dbg_r28,
    input  wire [`XLEN-1:0] dbg_r29,
    input  wire [`XLEN-1:0] dbg_r30,
    input  wire [`XLEN-1:0] dbg_r31,

    // ------------------------------------------------------------
    // Outputs
    // ------------------------------------------------------------
    output wire uart_tx_line,
    output wire debug_busy
);

    // ============================================================
    // Event type encoding
    // ============================================================
    localparam EVT_WB = 1'b0;
    localparam EVT_STORE = 1'b1;

    // ============================================================
    // FIFO parameters
    // ============================================================
    localparam FIFO_DEPTH = 20;
    localparam FIFO_W = 166;

    // ============================================================
    // Debug FSM states
    // ============================================================
    localparam [2:0] DBG_IDLE = 3'd0;
    localparam [2:0] DBG_SEND_TRACE = 3'd1;
    localparam [2:0] DBG_SEND_HALT_INTRO = 3'd2;
    localparam [2:0] DBG_SEND_HALT_DUMP = 3'd3;
    localparam [2:0] DBG_DONE = 3'd4;

    // ============================================================
    // Byte-send sub FSM states
    // ============================================================
    localparam [1:0] SS_START = 2'd0;
    localparam [1:0] SS_WAIT_BUSY_HI = 2'd1;
    localparam [1:0] SS_WAIT_BUSY_LO = 2'd2;

    // ============================================================
    // Combinational event detection (level signals)
    // ============================================================
    wire is_wb_event = (state_out == `S_WRITEBACK) && rd_we;
    wire is_store_event = (state_out == `S_MEM_WRITE) && d_ready && d_we;
    wire is_halt_event = halt || (state_out == `S_HALT);

    // ============================================================
    // One-shot edge detection
    // Each event fires for exactly one clock cycle on the 0->1
    // transition of its level signal, preventing duplicate FIFO
    // entries when a CPU state persists for multiple cycles.
    // ============================================================
    reg prev_wb_event;
    reg prev_store_event;
    reg prev_halt_event;

    always @(posedge clk) begin
        if (rst) begin
            prev_wb_event <= 1'b0;
            prev_store_event <= 1'b0;
            prev_halt_event <= 1'b0;
        end else begin
            prev_wb_event <= is_wb_event;
            prev_store_event <= is_store_event;
            prev_halt_event <= is_halt_event;
        end
    end

    wire wb_pulse = is_wb_event && !prev_wb_event;
    wire store_pulse = is_store_event && !prev_store_event;
    wire halt_pulse = is_halt_event  && !prev_halt_event;

    // ============================================================
    // FIFO storage, pointers, count
    // ============================================================
    reg [FIFO_W-1:0] fifo_mem [0:FIFO_DEPTH-1];
    reg [4:0] fifo_wr_ptr;
    reg [4:0] fifo_rd_ptr;
    reg [4:0] fifo_count;

    wire fifo_empty = (fifo_count == 5'd0);
    wire fifo_full = (fifo_count == 5'd20);

    // ============================================================
    // FIFO push / pop control wires
    // Push: rising-edge pulse only; gated once halt has been seen.
    // Pop:  FSM is idle and FIFO has data to drain.
    // ============================================================
    wire do_push = (wb_pulse || store_pulse) && !fifo_full && !halt_pending;

    wire do_pop = (dbg_state == DBG_IDLE) && !fifo_empty;

    // ============================================================
    // FSM / counter state
    // ============================================================
    reg [2:0] dbg_state;
    reg [1:0] send_sub;
    reg [6:0] byte_idx;
    reg [4:0] dump_idx;
    reg halt_pending;

    reg tx_start;
    wire tx_busy;

    // ============================================================
    // Snapshot registers (loaded from FIFO head on pop)
    // ============================================================
    reg snap_event_type;
    reg [`XLEN-1:0] snap_pc;
    reg [`XLEN-1:0] snap_instr;
    reg [`REG_ADDR_W-1:0] snap_rd_idx;
    reg [`XLEN-1:0] snap_wb_data;
    reg [`XLEN-1:0] snap_alu_result;
    reg [`XLEN-1:0] snap_store_data;

    // ============================================================
    // FIFO state: push, pop, count update (separate always block
    // so simultaneous push+pop is handled correctly)
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            fifo_wr_ptr <= 5'd0;
            fifo_rd_ptr <= 5'd0;
            fifo_count <= 5'd0;
        end else begin
            if (do_push) begin
                fifo_mem[fifo_wr_ptr] <= {
                    store_pulse,      // [165] 1=STORE, 0=WB
                    instr_pc,         // [164:133]
                    instr,            // [132:101]
                    rd_idx,           // [100:96]
                    wb_data_out,      // [95:64]
                    alu_result_out,   // [63:32]
                    store_data_out    // [31:0]
                };
                fifo_wr_ptr <= (fifo_wr_ptr == 5'd19) ? 5'd0 : fifo_wr_ptr + 5'd1;
            end

            if (do_pop) begin
                fifo_rd_ptr <= (fifo_rd_ptr == 5'd19) ? 5'd0 : fifo_rd_ptr + 5'd1;
            end

            // Count: push only +1, pop only -1, simultaneous = unchanged
            case ({do_push, do_pop})
                2'b10: fifo_count <= fifo_count + 5'd1;
                2'b01: fifo_count <= fifo_count - 5'd1;
                default: ; // 2'b00 or 2'b11: no change
            endcase
        end
    end

    // ============================================================
    // Register-dump multiplexer (halted CPU; purely combinational)
    // ============================================================
    reg [`XLEN-1:0] selected_dump_reg;
    always @(*) begin
        case (dump_idx)
            5'd0: selected_dump_reg = dbg_r0;
            5'd1: selected_dump_reg = dbg_r1;
            5'd2: selected_dump_reg = dbg_r2;
            5'd3: selected_dump_reg = dbg_r3;
            5'd4: selected_dump_reg = dbg_r4;
            5'd5: selected_dump_reg = dbg_r5;
            5'd6: selected_dump_reg = dbg_r6;
            5'd7: selected_dump_reg = dbg_r7;
            5'd8: selected_dump_reg = dbg_r8;
            5'd9: selected_dump_reg = dbg_r9;
            5'd10: selected_dump_reg = dbg_r10;
            5'd11: selected_dump_reg = dbg_r11;
            5'd12: selected_dump_reg = dbg_r12;
            5'd13: selected_dump_reg = dbg_r13;
            5'd14: selected_dump_reg = dbg_r14;
            5'd15: selected_dump_reg = dbg_r15;
            5'd16: selected_dump_reg = dbg_r16;
            5'd17: selected_dump_reg = dbg_r17;
            5'd18: selected_dump_reg = dbg_r18;
            5'd19: selected_dump_reg = dbg_r19;
            5'd20: selected_dump_reg = dbg_r20;
            5'd21: selected_dump_reg = dbg_r21;
            5'd22: selected_dump_reg = dbg_r22;
            5'd23: selected_dump_reg = dbg_r23;
            5'd24: selected_dump_reg = dbg_r24;
            5'd25: selected_dump_reg = dbg_r25;
            5'd26: selected_dump_reg = dbg_r26;
            5'd27: selected_dump_reg = dbg_r27;
            5'd28: selected_dump_reg = dbg_r28;
            5'd29: selected_dump_reg = dbg_r29;
            5'd30: selected_dump_reg = dbg_r30;
            5'd31: selected_dump_reg = dbg_r31;
            default: selected_dump_reg = {`XLEN{1'b0}};
        endcase
    end

    // ============================================================
    // Helper functions
    // ============================================================
    function [3:0] nib_of;
        input [`XLEN-1:0] word;
        input [2:0] idx;  // 0 = MS nibble, 7 = LS nibble
        begin
            case (idx)
                3'd0: nib_of = word[31:28];
                3'd1: nib_of = word[27:24];
                3'd2: nib_of = word[23:20];
                3'd3: nib_of = word[19:16];
                3'd4: nib_of = word[15:12];
                3'd5: nib_of = word[11:8];
                3'd6: nib_of = word[7:4];
                3'd7: nib_of = word[3:0];
                default: nib_of = 4'd0;
            endcase
        end
    endfunction

    function [7:0] nib2ascii;
        input [3:0] n;
        begin
            nib2ascii = (n < 4'd10) ? (8'h30 + {4'b0, n}) : (8'h37 + {4'b0, n});
        end
    endfunction

    function [7:0] hex_of;
        input [`XLEN-1:0] word;
        input [2:0] idx;
        begin
            hex_of = nib2ascii(nib_of(word, idx));
        end
    endfunction

    // ------------------------------------------------------------
    // Decimal tens/ones for dump_idx (0..31)
    // ------------------------------------------------------------
    wire [3:0] dump_tens =
        (dump_idx >= 5'd30) ? 4'd3 :
        (dump_idx >= 5'd20) ? 4'd2 :
        (dump_idx >= 5'd10) ? 4'd1 : 4'd0;

    wire [4:0] dump_ones =
        (dump_tens == 4'd3) ? (dump_idx - 5'd30) :
        (dump_tens == 4'd2) ? (dump_idx - 5'd20) :
        (dump_tens == 4'd1) ? (dump_idx - 5'd10) :
                               dump_idx;

    wire [7:0] dump_tens_ascii = 8'h30 + {4'b0, dump_tens};
    wire [7:0] dump_ones_ascii = 8'h30 + {3'b0, dump_ones};

    // ------------------------------------------------------------
    // rd_idx as two hex digits
    // ------------------------------------------------------------
    wire [7:0] rd_hi_ascii = nib2ascii({3'b0, snap_rd_idx[4]});
    wire [7:0] rd_lo_ascii = nib2ascii(snap_rd_idx[3:0]);

    // ============================================================
    // Line-length selector
    //   WB    : indices 0..42 -> last = 42
    //   STORE : indices 0..49 -> last = 49
    //   INTRO : indices 0..5  -> last = 5
    //   DUMP  : indices 0..13 -> last = 13
    // ============================================================
    reg [6:0] last_byte_idx;
    always @(*) begin
        case (dbg_state)
            DBG_SEND_TRACE:
                last_byte_idx = (snap_event_type == EVT_STORE) ? 7'd49 : 7'd42;
            DBG_SEND_HALT_INTRO: last_byte_idx = 7'd5;
            DBG_SEND_HALT_DUMP: last_byte_idx = 7'd13;
            default: last_byte_idx = 7'd0;
        endcase
    end

    // ============================================================
    // Character emission (combinational)
    // ============================================================
    reg [7:0] char_out;
    always @(*) begin
        char_out = 8'h20;  // default: space

        case (dbg_state)

            // --------------------------------------------------
            DBG_SEND_TRACE: begin

                if (snap_event_type == EVT_WB) begin
                    // "PC=XXXXXXXX IR=XXXXXXXX RD=XX WB=XXXXXXXX\r\n"
                    //  0123456789...
                    case (byte_idx)
                        7'd0: char_out = "P";
                        7'd1: char_out = "C";
                        7'd2: char_out = "=";
                        7'd3: char_out = hex_of(snap_pc, 3'd0);
                        7'd4: char_out = hex_of(snap_pc, 3'd1);
                        7'd5: char_out = hex_of(snap_pc, 3'd2);
                        7'd6: char_out = hex_of(snap_pc, 3'd3);
                        7'd7: char_out = hex_of(snap_pc, 3'd4);
                        7'd8: char_out = hex_of(snap_pc, 3'd5);
                        7'd9: char_out = hex_of(snap_pc, 3'd6);
                        7'd10: char_out = hex_of(snap_pc, 3'd7);
                        7'd11: char_out = " ";
                        7'd12: char_out = "I";
                        7'd13: char_out = "R";
                        7'd14: char_out = "=";
                        7'd15: char_out = hex_of(snap_instr, 3'd0);
                        7'd16: char_out = hex_of(snap_instr, 3'd1);
                        7'd17: char_out = hex_of(snap_instr, 3'd2);
                        7'd18: char_out = hex_of(snap_instr, 3'd3);
                        7'd19: char_out = hex_of(snap_instr, 3'd4);
                        7'd20: char_out = hex_of(snap_instr, 3'd5);
                        7'd21: char_out = hex_of(snap_instr, 3'd6);
                        7'd22: char_out = hex_of(snap_instr, 3'd7);
                        7'd23: char_out = " ";
                        7'd24: char_out = "R";
                        7'd25: char_out = "D";
                        7'd26: char_out = "=";
                        7'd27: char_out = rd_hi_ascii;
                        7'd28: char_out = rd_lo_ascii;
                        7'd29: char_out = " ";
                        7'd30: char_out = "W";
                        7'd31: char_out = "B";
                        7'd32: char_out = "=";
                        7'd33: char_out = hex_of(snap_wb_data, 3'd0);
                        7'd34: char_out = hex_of(snap_wb_data, 3'd1);
                        7'd35: char_out = hex_of(snap_wb_data, 3'd2);
                        7'd36: char_out = hex_of(snap_wb_data, 3'd3);
                        7'd37: char_out = hex_of(snap_wb_data, 3'd4);
                        7'd38: char_out = hex_of(snap_wb_data, 3'd5);
                        7'd39: char_out = hex_of(snap_wb_data, 3'd6);
                        7'd40: char_out = hex_of(snap_wb_data, 3'd7);
                        7'd41: char_out = 8'h0D;
                        7'd42: char_out = 8'h0A;
                        default: char_out = 8'h20;
                    endcase

                end else begin
                    // "PC=XXXXXXXX IR=XXXXXXXX ST A=XXXXXXXX D=XXXXXXXX\r\n"
                    case (byte_idx)
                        7'd0: char_out = "P";
                        7'd1: char_out = "C";
                        7'd2: char_out = "=";
                        7'd3: char_out = hex_of(snap_pc, 3'd0);
                        7'd4: char_out = hex_of(snap_pc, 3'd1);
                        7'd5: char_out = hex_of(snap_pc, 3'd2);
                        7'd6: char_out = hex_of(snap_pc, 3'd3);
                        7'd7: char_out = hex_of(snap_pc, 3'd4);
                        7'd8: char_out = hex_of(snap_pc, 3'd5);
                        7'd9: char_out = hex_of(snap_pc, 3'd6);
                        7'd10: char_out = hex_of(snap_pc, 3'd7);
                        7'd11: char_out = " ";
                        7'd12: char_out = "I";
                        7'd13: char_out = "R";
                        7'd14: char_out = "=";
                        7'd15: char_out = hex_of(snap_instr, 3'd0);
                        7'd16: char_out = hex_of(snap_instr, 3'd1);
                        7'd17: char_out = hex_of(snap_instr, 3'd2);
                        7'd18: char_out = hex_of(snap_instr, 3'd3);
                        7'd19: char_out = hex_of(snap_instr, 3'd4);
                        7'd20: char_out = hex_of(snap_instr, 3'd5);
                        7'd21: char_out = hex_of(snap_instr, 3'd6);
                        7'd22: char_out = hex_of(snap_instr, 3'd7);
                        7'd23: char_out = " ";
                        7'd24: char_out = "S";
                        7'd25: char_out = "T";
                        7'd26: char_out = " ";
                        7'd27: char_out = "A";
                        7'd28: char_out = "=";
                        7'd29: char_out = hex_of(snap_alu_result, 3'd0);
                        7'd30: char_out = hex_of(snap_alu_result, 3'd1);
                        7'd31: char_out = hex_of(snap_alu_result, 3'd2);
                        7'd32: char_out = hex_of(snap_alu_result, 3'd3);
                        7'd33: char_out = hex_of(snap_alu_result, 3'd4);
                        7'd34: char_out = hex_of(snap_alu_result, 3'd5);
                        7'd35: char_out = hex_of(snap_alu_result, 3'd6);
                        7'd36: char_out = hex_of(snap_alu_result, 3'd7);
                        7'd37: char_out = " ";
                        7'd38: char_out = "D";
                        7'd39: char_out = "=";
                        7'd40: char_out = hex_of(snap_store_data, 3'd0);
                        7'd41: char_out = hex_of(snap_store_data, 3'd1);
                        7'd42: char_out = hex_of(snap_store_data, 3'd2);
                        7'd43: char_out = hex_of(snap_store_data, 3'd3);
                        7'd44: char_out = hex_of(snap_store_data, 3'd4);
                        7'd45: char_out = hex_of(snap_store_data, 3'd5);
                        7'd46: char_out = hex_of(snap_store_data, 3'd6);
                        7'd47: char_out = hex_of(snap_store_data, 3'd7);
                        7'd48: char_out = 8'h0D;
                        7'd49: char_out = 8'h0A;
                        default: char_out = 8'h20;
                    endcase
                end
            end

            // --------------------------------------------------
            // "HALT\r\n"
            DBG_SEND_HALT_INTRO: begin
                case (byte_idx)
                    7'd0: char_out = "H";
                    7'd1: char_out = "A";
                    7'd2: char_out = "L";
                    7'd3: char_out = "T";
                    7'd4: char_out = 8'h0D;
                    7'd5: char_out = 8'h0A;
                    default: char_out = 8'h20;
                endcase
            end

            // --------------------------------------------------
            // "rNN=XXXXXXXX\r\n"
            DBG_SEND_HALT_DUMP: begin
                case (byte_idx)
                    7'd0: char_out = "r";
                    7'd1: char_out = dump_tens_ascii;
                    7'd2: char_out = dump_ones_ascii;
                    7'd3: char_out = "=";
                    7'd4: char_out = hex_of(selected_dump_reg, 3'd0);
                    7'd5: char_out = hex_of(selected_dump_reg, 3'd1);
                    7'd6: char_out = hex_of(selected_dump_reg, 3'd2);
                    7'd7: char_out = hex_of(selected_dump_reg, 3'd3);
                    7'd8: char_out = hex_of(selected_dump_reg, 3'd4);
                    7'd9: char_out = hex_of(selected_dump_reg, 3'd5);
                    7'd10: char_out = hex_of(selected_dump_reg, 3'd6);
                    7'd11: char_out = hex_of(selected_dump_reg, 3'd7);
                    7'd12: char_out = 8'h0D;
                    7'd13: char_out = 8'h0A;
                    default: char_out = 8'h20;
                endcase
            end

            default: char_out = 8'h20;
        endcase
    end

    // ============================================================
    // Main sequential block: FSM + snapshot capture + halt_pending
    // FIFO pointer/count updates are in their own always block above.
    // ============================================================
    always @(posedge clk) begin
        if (rst) begin
            dbg_state <= DBG_IDLE;
            send_sub <= SS_START;
            byte_idx <= 7'd0;
            dump_idx <= 5'd0;
            tx_start <= 1'b0;
            halt_pending <= 1'b0;

            snap_event_type <= EVT_WB;
            snap_pc <= {`XLEN{1'b0}};
            snap_instr <= {`XLEN{1'b0}};
            snap_rd_idx <= {`REG_ADDR_W{1'b0}};
            snap_wb_data <= {`XLEN{1'b0}};
            snap_alu_result <= {`XLEN{1'b0}};
            snap_store_data <= {`XLEN{1'b0}};
        end else begin
            tx_start <= 1'b0;

            // Latch halt on rising edge only; sticky until reset
            if (halt_pulse)
                halt_pending <= 1'b1;

            case (dbg_state)

                // --------------------------------------------------
                // Idle: drain FIFO first; transition to halt only
                // when FIFO is empty and halt_pending is set.
                // --------------------------------------------------
                DBG_IDLE: begin
                    if (do_pop) begin
                        // Load snap registers from FIFO head
                        snap_event_type <= fifo_mem[fifo_rd_ptr][165];
                        snap_pc <= fifo_mem[fifo_rd_ptr][164:133];
                        snap_instr <= fifo_mem[fifo_rd_ptr][132:101];
                        snap_rd_idx <= fifo_mem[fifo_rd_ptr][100:96];
                        snap_wb_data <= fifo_mem[fifo_rd_ptr][95:64];
                        snap_alu_result <= fifo_mem[fifo_rd_ptr][63:32];
                        snap_store_data <= fifo_mem[fifo_rd_ptr][31:0];

                        byte_idx <= 7'd0;
                        send_sub <= SS_START;
                        dbg_state <= DBG_SEND_TRACE;
                    end else if (halt_pending) begin
                        byte_idx <= 7'd0;
                        send_sub <= SS_START;
                        dbg_state <= DBG_SEND_HALT_INTRO;
                    end
                end

                // --------------------------------------------------
                // Transmit one line; advance FSM on end-of-line
                // --------------------------------------------------
                DBG_SEND_TRACE,
                DBG_SEND_HALT_INTRO,
                DBG_SEND_HALT_DUMP: begin
                    case (send_sub)

                        SS_START: begin
                            tx_start <= 1'b1;
                            send_sub <= SS_WAIT_BUSY_HI;
                        end

                        SS_WAIT_BUSY_HI: begin
                            if (tx_busy)
                                send_sub <= SS_WAIT_BUSY_LO;
                        end

                        SS_WAIT_BUSY_LO: begin
                            if (!tx_busy) begin
                                if (byte_idx == last_byte_idx) begin
                                    byte_idx <= 7'd0;
                                    send_sub <= SS_START;

                                    if (dbg_state == DBG_SEND_TRACE) begin
                                        // Return to idle; may pop next entry or go to halt
                                        dbg_state <= DBG_IDLE;
                                    end else if (dbg_state == DBG_SEND_HALT_INTRO) begin
                                        dump_idx  <= 5'd0;
                                        dbg_state <= DBG_SEND_HALT_DUMP;
                                    end else begin
                                        // DBG_SEND_HALT_DUMP
                                        if (dump_idx == 5'd31)
                                            dbg_state <= DBG_DONE;
                                        else
                                            dump_idx <= dump_idx + 5'd1;
                                    end
                                end else begin
                                    byte_idx <= byte_idx + 7'd1;
                                    send_sub <= SS_START;
                                end
                            end
                        end

                        default: send_sub <= SS_START;
                    endcase
                end

                // --------------------------------------------------
                // Terminal state after register dump
                // --------------------------------------------------
                DBG_DONE: begin
                    // Stays here. Reset is the only exit.
                end

                default: dbg_state <= DBG_IDLE;

            endcase
        end
    end

    // ============================================================
    // UART TX instance
    // ============================================================
    uart_tx #(
        .CLKS_PER_BIT(CLKS_PER_BIT)
    ) u_uart_tx (
        .clk(clk),
        .rst(rst),
        .tx_start(tx_start),
        .tx_data(char_out),
        .tx_serial(uart_tx_line),
        .tx_busy(tx_busy)
    );

    // ============================================================
    // Status outputs
    // ============================================================
    assign debug_busy = (dbg_state != DBG_IDLE) && (dbg_state != DBG_DONE);

endmodule