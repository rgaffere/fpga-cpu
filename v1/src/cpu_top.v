`timescale 1ns / 1ps
`include "defines.vh"

module cpu_top #(
    parameter MEM_BYTES = 65536,
    parameter INIT_FILE = "test_mem.hex"
)(
    input  wire clk,
    input  wire rst_n, // alchitry au v2 polarity is reversed
    output wire halt_out, // adding this so the design isnt removed during synthesis
    output wire uart_tx_line,
    output wire debug_busy
);

    localparam integer UART_CLKS_PER_BIT = 868;

    wire rst = ~rst_n;
    // ============================================================
    // Interconnect: control_unit <-> datapath
    // ============================================================
    wire [`XLEN-1:0] instr;

    wire                     pc_we;
    wire [`PC_SEL_W-1:0]     pc_sel;

    wire [`ALU_ASEL_W-1:0]   alu_asel;
    wire [`ALU_BSEL_W-1:0]   alu_bsel;
    wire [`ALU_OP_W-1:0]     alu_op;

    wire                     rd_we;
    wire [`WB_SEL_W-1:0]     wb_sel;

    wire                     flags_we;

    wire                     d_req;
    wire                     d_we;
    wire [`MEM_SIZE_W-1:0]   d_size;
    wire                     load_ext_sel;

    wire                     if_req;
    wire                     branch_taken;
    wire                     halt;

    wire [`XLEN-1:0]         pc_out;
    wire [`XLEN-1:0]         fetched_instr;
    wire                     if_ready;
    wire                     if_fault;
    wire                     if_misaligned;
    wire                     d_ready;
    wire                     d_fault;
    wire                     d_misaligned;

    wire [5:0]               opcode;
    wire [5:0]               funct6;
    wire [`REG_ADDR_W-1:0]   rd_idx;
    wire [`REG_ADDR_W-1:0]   rs1_idx;
    wire [`REG_ADDR_W-1:0]   rs2_idx;

    wire                     flag_z;
    wire                     flag_n;
    wire                     flag_c;
    wire                     flag_v;

    wire [`XLEN-1:0]         alu_result_out;
    wire [`XLEN-1:0]         mem_rdata_out;
    wire [`XLEN-1:0]         wb_data_out;

    wire [`FSM_STATE_W-1:0]  state_out;
    wire                     alu_latch;

    assign halt_out = halt; // So the whole thing doesnt delete during synth
    // ============================================================
    // Trap interface
    // ============================================================
    wire                     trap_enter;
    wire [`TRAP_CAUSE_W-1:0] trap_cause;

    wire [`XLEN-1:0]         epc_out;
    wire [`XLEN-1:0]         cause_out;
    wire [`XLEN-1:0]         status_out;
    wire [`XLEN-1:0]         instr_pc_out;

    wire [`XLEN-1:0] trap_pc_in;
    assign trap_pc_in = if_fault ? pc_out : instr_pc_out;

    // Minimal interrupt hook for now
    wire ext_irq = 1'b0;

    // Some crazy debug stuff

    wire [`XLEN-1:0]         store_data_out;

    wire [`XLEN-1:0]         dbg_r0;
    wire [`XLEN-1:0]         dbg_r1;
    wire [`XLEN-1:0]         dbg_r2;
    wire [`XLEN-1:0]         dbg_r3;
    wire [`XLEN-1:0]         dbg_r4;
    wire [`XLEN-1:0]         dbg_r5;
    wire [`XLEN-1:0]         dbg_r6;
    wire [`XLEN-1:0]         dbg_r7;
    wire [`XLEN-1:0]         dbg_r8;
    wire [`XLEN-1:0]         dbg_r9;
    wire [`XLEN-1:0]         dbg_r10;
    wire [`XLEN-1:0]         dbg_r11;
    wire [`XLEN-1:0]         dbg_r12;
    wire [`XLEN-1:0]         dbg_r13;
    wire [`XLEN-1:0]         dbg_r14;
    wire [`XLEN-1:0]         dbg_r15;
    wire [`XLEN-1:0]         dbg_r16;
    wire [`XLEN-1:0]         dbg_r17;
    wire [`XLEN-1:0]         dbg_r18;
    wire [`XLEN-1:0]         dbg_r19;
    wire [`XLEN-1:0]         dbg_r20;
    wire [`XLEN-1:0]         dbg_r21;
    wire [`XLEN-1:0]         dbg_r22;
    wire [`XLEN-1:0]         dbg_r23;
    wire [`XLEN-1:0]         dbg_r24;
    wire [`XLEN-1:0]         dbg_r25;
    wire [`XLEN-1:0]         dbg_r26;
    wire [`XLEN-1:0]         dbg_r27;
    wire [`XLEN-1:0]         dbg_r28;
    wire [`XLEN-1:0]         dbg_r29;
    wire [`XLEN-1:0]         dbg_r30;
    wire [`XLEN-1:0]         dbg_r31;

    // ============================================================
    // Control Unit
    // ============================================================
    control_unit u_control_unit (
        .clk          (clk),
        .rst          (rst),

        .fetched_instr(fetched_instr),
        .if_ready     (if_ready),
        .if_fault     (if_fault),
        .if_misaligned(if_misaligned),

        .d_ready      (d_ready),
        .d_fault      (d_fault),
        .d_misaligned (d_misaligned),

        .flag_z       (flag_z),
        .flag_n       (flag_n),
        .flag_c       (flag_c),
        .flag_v       (flag_v),

        .epc_in       (epc_out),

        .instr        (instr),

        .pc_we        (pc_we),
        .pc_sel       (pc_sel),

        .alu_asel     (alu_asel),
        .alu_bsel     (alu_bsel),
        .alu_op       (alu_op),

        .rd_we        (rd_we),
        .wb_sel       (wb_sel),

        .flags_we     (flags_we),

        .d_req        (d_req),
        .d_we         (d_we),
        .d_size       (d_size),
        .load_ext_sel (load_ext_sel),

        .if_req       (if_req),
        .branch_taken (branch_taken),
        .halt         (halt),

        .trap_enter   (trap_enter),
        .trap_cause   (trap_cause),

        .alu_latch    (alu_latch),
        .state_out    (state_out)
    );

    // ============================================================
    // Datapath
    // ============================================================
    datapath #(
        .MEM_BYTES (MEM_BYTES),
        .INIT_FILE (INIT_FILE)
    ) u_datapath (
        .clk          (clk),
        .rst          (rst),

        .instr        (instr),

        .pc_we        (pc_we),
        .pc_sel       (pc_sel),

        .alu_latch    (alu_latch),
        .alu_asel     (alu_asel),
        .alu_bsel     (alu_bsel),
        .alu_op       (alu_op),

        .rd_we        (rd_we),
        .wb_sel       (wb_sel),

        .flags_we     (flags_we),

        .d_req        (d_req),
        .d_we         (d_we),
        .d_size       (d_size),
        .load_ext_sel (load_ext_sel),

        .if_req       (if_req),

        .branch_taken (branch_taken),
        .halt         (halt),

        .epc_in       (epc_out),

        .pc_out       (pc_out),
        .fetched_instr(fetched_instr),
        .if_ready     (if_ready),
        .if_fault     (if_fault),
        .if_misaligned(if_misaligned),
        .d_ready      (d_ready),
        .d_fault      (d_fault),
        .d_misaligned (d_misaligned),
        .instr_pc_out (instr_pc_out),

        .opcode       (opcode),
        .funct6       (funct6),
        .rd_idx       (rd_idx),
        .rs1_idx      (rs1_idx),
        .rs2_idx      (rs2_idx),

        .flag_z       (flag_z),
        .flag_n       (flag_n),
        .flag_c       (flag_c),
        .flag_v       (flag_v),

        .alu_result_out(alu_result_out),
        .mem_rdata_out(mem_rdata_out),
        .wb_data_out  (wb_data_out),
        .store_data_out(store_data_out),

        .dbg_r0       (dbg_r0),
        .dbg_r1       (dbg_r1),
        .dbg_r2       (dbg_r2),
        .dbg_r3       (dbg_r3),
        .dbg_r4       (dbg_r4),
        .dbg_r5       (dbg_r5),
        .dbg_r6       (dbg_r6),
        .dbg_r7       (dbg_r7),
        .dbg_r8       (dbg_r8),
        .dbg_r9       (dbg_r9),
        .dbg_r10      (dbg_r10),
        .dbg_r11      (dbg_r11),
        .dbg_r12      (dbg_r12),
        .dbg_r13      (dbg_r13),
        .dbg_r14      (dbg_r14),
        .dbg_r15      (dbg_r15),
        .dbg_r16      (dbg_r16),
        .dbg_r17      (dbg_r17),
        .dbg_r18      (dbg_r18),
        .dbg_r19      (dbg_r19),
        .dbg_r20      (dbg_r20),
        .dbg_r21      (dbg_r21),
        .dbg_r22      (dbg_r22),
        .dbg_r23      (dbg_r23),
        .dbg_r24      (dbg_r24),
        .dbg_r25      (dbg_r25),
        .dbg_r26      (dbg_r26),
        .dbg_r27      (dbg_r27),
        .dbg_r28      (dbg_r28),
        .dbg_r29      (dbg_r29),
        .dbg_r30      (dbg_r30),
        .dbg_r31      (dbg_r31)
    );

    // ============================================================
    // Trap Registers
    // ============================================================
    trap_regs u_trap_regs (
        .clk        (clk),
        .rst        (rst),

        .trap_enter (trap_enter),
        .trap_cause (trap_cause),
        .pc_in      (trap_pc_in),

        .eret       (state_out == `S_TRAP_RETURN),

        .ext_irq    (ext_irq),

        .epc_out    (epc_out),
        .cause_out  (cause_out),
        .status_out (status_out)
    );

    // ============================================================
    // Debug Module
    // ============================================================

        debug #(
            .CLKS_PER_BIT(UART_CLKS_PER_BIT)
        ) u_debug (
        .clk           (clk),
        .rst           (rst),
        .instr         (instr),
        .instr_pc      (instr_pc_out),
        .rd_idx        (rd_idx),
        .alu_result_out(alu_result_out),
        .wb_data_out   (wb_data_out),
        .store_data_out(store_data_out),
        .state_out     (state_out),
        .rd_we         (rd_we),
        .d_we          (d_we),
        .d_ready       (d_ready),
        .halt          (halt),

        .dbg_r0        (dbg_r0),
        .dbg_r1        (dbg_r1),
        .dbg_r2        (dbg_r2),
        .dbg_r3        (dbg_r3),
        .dbg_r4        (dbg_r4),
        .dbg_r5        (dbg_r5),
        .dbg_r6        (dbg_r6),
        .dbg_r7        (dbg_r7),
        .dbg_r8        (dbg_r8),
        .dbg_r9        (dbg_r9),
        .dbg_r10       (dbg_r10),
        .dbg_r11       (dbg_r11),
        .dbg_r12       (dbg_r12),
        .dbg_r13       (dbg_r13),
        .dbg_r14       (dbg_r14),
        .dbg_r15       (dbg_r15),
        .dbg_r16       (dbg_r16),
        .dbg_r17       (dbg_r17),
        .dbg_r18       (dbg_r18),
        .dbg_r19       (dbg_r19),
        .dbg_r20       (dbg_r20),
        .dbg_r21       (dbg_r21),
        .dbg_r22       (dbg_r22),
        .dbg_r23       (dbg_r23),
        .dbg_r24       (dbg_r24),
        .dbg_r25       (dbg_r25),
        .dbg_r26       (dbg_r26),
        .dbg_r27       (dbg_r27),
        .dbg_r28       (dbg_r28),
        .dbg_r29       (dbg_r29),
        .dbg_r30       (dbg_r30),
        .dbg_r31       (dbg_r31),

        .uart_tx_line  (uart_tx_line),
        .debug_busy    (debug_busy)
    );

endmodule