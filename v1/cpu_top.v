`timescale 1ns / 1ps
`include "defines.vh"

module cpu_top #(
    parameter MEM_BYTES = 65536,
    parameter INIT_FILE = ""
)(
    input  wire clk,
    input  wire rst
);

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
        .wb_data_out  (wb_data_out)
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

endmodule