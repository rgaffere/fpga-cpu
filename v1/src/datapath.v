`timescale 1ns / 1ps
`include "defines.vh"

module datapath #(
    parameter MEM_BYTES = 65536,
    parameter INIT_FILE = ""
)(
    input  wire                     clk,
    input  wire                     rst,

    // ============================================================
    // Current instruction from control_unit IR
    // control_unit owns the IR per repo structure
    // ============================================================
    input  wire [`XLEN-1:0]         instr,

    // ============================================================
    // Control signals from control_unit
    // ============================================================
    input  wire                     pc_we,
    input  wire [`PC_SEL_W-1:0]     pc_sel,

	input  wire                     alu_latch,
    input  wire [`ALU_ASEL_W-1:0]   alu_asel,
    input  wire [`ALU_BSEL_W-1:0]   alu_bsel,
    input  wire [`ALU_OP_W-1:0]     alu_op,

    input  wire                     rd_we,
    input  wire [`WB_SEL_W-1:0]     wb_sel,

    input  wire                     flags_we,

    // memory-side controls for current instruction
    input  wire                     d_req,
    input  wire                     d_we,
    input  wire [`MEM_SIZE_W-1:0]   d_size,
    input  wire                     load_ext_sel,   // 1=sign, 0=zero

    // fetch control
    input  wire                     if_req,

    // branch / trap / halt control
    input  wire                     branch_taken,
    input  wire                     halt,

    // trap/return support hooks
    input  wire [`XLEN-1:0]         epc_in,

    // ============================================================
    // Outputs back to control_unit / cpu_top
    // ============================================================
    output wire [`XLEN-1:0]         pc_out,
    output wire [`XLEN-1:0]         fetched_instr,
    output wire                     if_ready,
    output wire                     if_fault,
    output wire                     d_ready,
    output wire                     d_fault,
	output wire [`XLEN-1:0] 		instr_pc_out,

    // decoded visibility/status
    output wire [5:0]               opcode,
    output wire [5:0]               funct6,
    output wire [`REG_ADDR_W-1:0]   rd_idx,
    output wire [`REG_ADDR_W-1:0]   rs1_idx,
    output wire [`REG_ADDR_W-1:0]   rs2_idx,

    output wire                     flag_z,
    output wire                     flag_n,
    output wire                     flag_c,
    output wire                     flag_v,

    // useful debug / verification taps
    output wire [`XLEN-1:0]         alu_result_out,
    output wire [`XLEN-1:0]         mem_rdata_out,
    output wire [`XLEN-1:0]         wb_data_out,
	
	output wire                     if_misaligned,
	output wire                     d_misaligned,

    // a bunch of debug ports. i make a better version later. but you gotta get it to work first, then optimize
    output wire [`XLEN-1:0]         store_data_out,

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

    // ============================================================
    // Instruction field extraction
    // ============================================================
    assign opcode = instr[`OPCODE_MSB:`OPCODE_LSB];
    assign funct6 = instr[`R_FUNCT6_MSB:`R_FUNCT6_LSB];

    // Common field extraction by format-compatible positions
    wire [`REG_ADDR_W-1:0] r_rd   = instr[`R_RD_MSB:`R_RD_LSB];
    wire [`REG_ADDR_W-1:0] r_rs1  = instr[`R_RS1_MSB:`R_RS1_LSB];
    wire [`REG_ADDR_W-1:0] r_rs2  = instr[`R_RS2_MSB:`R_RS2_LSB];

    wire [`REG_ADDR_W-1:0] i_rd   = instr[`I_RD_MSB:`I_RD_LSB];
    wire [`REG_ADDR_W-1:0] i_rs1  = instr[`I_RS1_MSB:`I_RS1_LSB];

    wire [`REG_ADDR_W-1:0] s_rs2  = instr[`S_RS2_MSB:`S_RS2_LSB];
    wire [`REG_ADDR_W-1:0] s_rs1  = instr[`S_RS1_MSB:`S_RS1_LSB];

    wire [`REG_ADDR_W-1:0] j_rd   = instr[`J_RD_MSB:`J_RD_LSB];
    wire [`REG_ADDR_W-1:0] u_rd   = instr[`U_RD_MSB:`U_RD_LSB];

    // Helper: is this a load opcode?
    wire is_load = (opcode == `OPC_LB)  || (opcode == `OPC_LBU) ||
                   (opcode == `OPC_LH)  || (opcode == `OPC_LHU) ||
                   (opcode == `OPC_LW);

    // Helper: is this a store opcode?
    wire is_store = (opcode == `OPC_SB) || (opcode == `OPC_SH) ||
                    (opcode == `OPC_SW);

    // Helper: is this an I-type opcode (uses i_rd / i_rs1)?
    wire is_itype = (opcode == `OPC_ADDI) || is_load || (opcode == `OPC_JALR);

    // Selected architectural indices
    assign rd_idx =
        (opcode == `OPC_RTYPE_ALU) ? r_rd  :
        (is_itype)                 ? i_rd  :
        (opcode == `OPC_JUMP)      ? j_rd  :
        (opcode == `OPC_UPPER)     ? u_rd  :
                                     `REG_ZERO;

    assign rs1_idx =
        (opcode == `OPC_RTYPE_ALU) ? r_rs1 :
        (is_itype)                 ? i_rs1 :
        (is_store)                 ? s_rs1 :
                                     `REG_ZERO;

    assign rs2_idx =
        (opcode == `OPC_RTYPE_ALU) ? r_rs2 :
        (is_store)                 ? s_rs2 :
                                     `REG_ZERO;

    // ============================================================
    // Immediate generation
    // ISA says imm16/imm21 are sign-extended unless otherwise stated.
    // U-type immediate is shifted left by LUI_SHIFT.
    // ============================================================
    wire [`XLEN-1:0] imm16_sext = {{16{instr[15]}}, instr[15:0]};
    wire [`XLEN-1:0] imm21_sext = {{11{instr[20]}}, instr[20:0]};
    wire [`XLEN-1:0] uimm_shift = {imm21_sext[`XLEN-`LUI_SHIFT-1:0], {`LUI_SHIFT{1'b0}}};

    // ============================================================
    // PC and PC-related values
    // ============================================================
    wire [`XLEN-1:0] pc_curr;
    reg  [`XLEN-1:0] next_pc;
	
	reg [`XLEN-1:0] instr_pc;

    wire [`XLEN-1:0] instr_pc_plus_4 = instr_pc + 32'd4;
	wire [`XLEN-1:0] pc_plus_4       = pc_curr + 32'd4;
	wire [`XLEN-1:0] branch_target   = instr_pc_plus_4 + imm16_sext;
	wire [`XLEN-1:0] jump_target     = instr_pc_plus_4 + imm21_sext;

    // JALR target = rs1 + signext(imm16)
    wire [`XLEN-1:0] rs1_data;
    wire [`XLEN-1:0] rs2_data;
    wire [`XLEN-1:0] jalr_target = rs1_data + imm16_sext;

    // ============================================================
    // Register file
    // ============================================================
    wire [`XLEN-1:0] wb_data;  // forward declaration (driven by WB mux below)

    assign store_data_out = rs2_data;

    regfile u_regfile (
        .clk      (clk),
        .rst      (rst),
        .rs1_addr (rs1_idx),
        .rs1_data (rs1_data),
        .rs2_addr (rs2_idx),
        .rs2_data (rs2_data),
        .rd_we    (rd_we && !halt),
        .rd_addr  (rd_idx),
        .rd_data  (wb_data),
        .dbg_r0   (dbg_r0),
        .dbg_r1   (dbg_r1),
        .dbg_r2   (dbg_r2),
        .dbg_r3   (dbg_r3),
        .dbg_r4   (dbg_r4),
        .dbg_r5   (dbg_r5),
        .dbg_r6   (dbg_r6),
        .dbg_r7   (dbg_r7),
        .dbg_r8   (dbg_r8),
        .dbg_r9   (dbg_r9),
        .dbg_r10  (dbg_r10),
        .dbg_r11  (dbg_r11),
        .dbg_r12  (dbg_r12),
        .dbg_r13  (dbg_r13),
        .dbg_r14  (dbg_r14),
        .dbg_r15  (dbg_r15),
        .dbg_r16  (dbg_r16),
        .dbg_r17  (dbg_r17),
        .dbg_r18  (dbg_r18),
        .dbg_r19  (dbg_r19),
        .dbg_r20  (dbg_r20),
        .dbg_r21  (dbg_r21),
        .dbg_r22  (dbg_r22),
        .dbg_r23  (dbg_r23),
        .dbg_r24  (dbg_r24),
        .dbg_r25  (dbg_r25),
        .dbg_r26  (dbg_r26),
        .dbg_r27  (dbg_r27),
        .dbg_r28  (dbg_r28),
        .dbg_r29  (dbg_r29),
        .dbg_r30  (dbg_r30),
        .dbg_r31  (dbg_r31)
    );

    // ============================================================
    // ALU operand muxes
    // ISA-required choices:
    // A: rs1 / PC / zero
    // B: rs2 / imm / 4 / shifted upper immediate
    // ============================================================
    reg [`XLEN-1:0] alu_a;
    reg [`XLEN-1:0] alu_b;

    always @(*) begin
        case (alu_asel)
            `ALU_ASEL_RS1:  alu_a = rs1_data;
            `ALU_ASEL_PC:   alu_a = pc_curr;
            `ALU_ASEL_ZERO: alu_a = {`XLEN{1'b0}};
            default:        alu_a = rs1_data;
        endcase
    end

    always @(*) begin
        case (alu_bsel)
            `ALU_BSEL_RS2:    alu_b = rs2_data;
            `ALU_BSEL_IMM:    alu_b = imm16_sext;
            `ALU_BSEL_CONST4: alu_b = 32'd4;
            `ALU_BSEL_UIMM:   alu_b = uimm_shift;
            default:          alu_b = rs2_data;
        endcase
    end

    // ============================================================
    // ALU
    // ============================================================
    wire [`XLEN-1:0] alu_result;
    wire alu_flag_z, alu_flag_n, alu_flag_c, alu_flag_v;

    alu u_alu (
        .a       (alu_a),
        .b       (alu_b),
        .alu_op  (alu_op),
        .result  (alu_result),
        .flag_z  (alu_flag_z),
        .flag_n  (alu_flag_n),
        .flag_c  (alu_flag_c),
        .flag_v  (alu_flag_v)
    );

	reg [`XLEN-1:0] alu_result_reg;

	always @(posedge clk) begin
		if (rst)
			alu_result_reg <= {`XLEN{1'b0}};
		else if (alu_latch)
			alu_result_reg <= alu_result;
	end

    // ============================================================
    // Architectural flags register
    // ISA says flags are only updated by flag-setting instructions.
    // ============================================================
    reg [`FLAGS_W-1:0] flags_reg;

    always @(posedge clk) begin
        if (rst) begin
            flags_reg <= {`FLAGS_W{1'b0}};
        end else if (flags_we && !halt) begin
            flags_reg[`FLAG_Z] <= alu_flag_z;
            flags_reg[`FLAG_N] <= alu_flag_n;
            flags_reg[`FLAG_C] <= alu_flag_c;
            flags_reg[`FLAG_V] <= alu_flag_v;
        end
    end

    assign flag_z = flags_reg[`FLAG_Z];
    assign flag_n = flags_reg[`FLAG_N];
    assign flag_c = flags_reg[`FLAG_C];
    assign flag_v = flags_reg[`FLAG_V];

    // ============================================================
    // Memory subsystem
    // - fetch uses PC
    // - data uses ALU result as effective address
    // ============================================================
    wire [`XLEN-1:0] if_rdata;
    wire [`XLEN-1:0] d_rdata_raw;

	mem_subsystem #(
		.MEM_BYTES (MEM_BYTES),
		.INIT_FILE (INIT_FILE)
	) u_mem_subsystem (
		.clk      (clk),
		.rst      (rst),

		.if_req   (if_req && !halt),
		.if_addr  (pc_curr),
		.if_rdata (if_rdata),
		.if_ready (if_ready),
		.if_fault (if_fault),
		.if_misaligned (if_misaligned),

		.d_req    (d_req && !halt),
		.d_we     (d_we),
		.d_size   (d_size),
		.d_addr   (alu_result_reg),
		.d_wdata  (rs2_data),
		.d_rdata  (d_rdata_raw),
		.d_ready  (d_ready),
		.d_fault  (d_fault),
		.d_misaligned  (d_misaligned)
	);

    assign fetched_instr = if_rdata;

    // ============================================================
    // Load-data extension logic
    // mem_subsystem returns raw byte/half/word packed in low bits.
    // ISA requires sign/zero extension based on load variant.
    // ============================================================
    reg [`XLEN-1:0] d_rdata_ext;

    always @(*) begin
        case (d_size)
            `MEM_SIZE_B: begin
                if (load_ext_sel)
                    d_rdata_ext = {{24{d_rdata_raw[7]}}, d_rdata_raw[7:0]};
                else
                    d_rdata_ext = {24'b0, d_rdata_raw[7:0]};
            end

            `MEM_SIZE_H: begin
                if (load_ext_sel)
                    d_rdata_ext = {{16{d_rdata_raw[15]}}, d_rdata_raw[15:0]};
                else
                    d_rdata_ext = {16'b0, d_rdata_raw[15:0]};
            end

            `MEM_SIZE_WD: begin
                d_rdata_ext = d_rdata_raw;
            end

            default: begin
                d_rdata_ext = {`XLEN{1'b0}};
            end
        endcase
    end

    assign mem_rdata_out = d_rdata_ext;

    // ============================================================
    // Writeback mux
    // ISA-required sources:
    //   ALU result
    //   Memory read data
    //   PC + 4
    //   Shifted immediate
    // ============================================================
	reg  [`XLEN-1:0] wb_mux_data;

	always @(*) begin
		case (wb_sel)
			`WB_SEL_ALU:  wb_mux_data = alu_result_reg;
			`WB_SEL_MEM:  wb_mux_data = d_rdata_ext;
			`WB_SEL_PC4:  wb_mux_data = instr_pc_plus_4;
			`WB_SEL_UIMM: wb_mux_data = uimm_shift;
			default:      wb_mux_data = alu_result_reg;
		endcase
	end

	assign wb_data     = wb_mux_data;
	assign wb_data_out = wb_mux_data;

    // ============================================================
    // PC source mux
    // ISA-required sources:
    //   PC + 4
    //   branch target
    //   jump target
    //   JALR target
    //   trap vector
    //   EPC
    // ============================================================

	always @(posedge clk) begin
		if (rst)
			instr_pc <= `RESET_PC;
		else if (if_ready && if_req)
			instr_pc <= pc_curr;
	end

	assign instr_pc_out = instr_pc;
	
    always @(*) begin
        case (pc_sel)
            `PC_SEL_PC4: begin
                next_pc = pc_plus_4;
            end

            `PC_SEL_BRANCH: begin
                // When branch_taken=1, pc_we=1 and we write branch_target.
                // When branch_taken=0, pc_we=0 so PC holds; this value is unused.
                next_pc = branch_target;
            end

            `PC_SEL_JUMP: begin
                next_pc = jump_target;
            end

            `PC_SEL_JALR: begin
                next_pc = jalr_target;
            end

            `PC_SEL_TRAP: begin
                next_pc = `TRAP_VECTOR;
            end

            `PC_SEL_EPC: begin
                next_pc = epc_in;
            end

            default: begin
                next_pc = pc_plus_4;
            end
        endcase
    end

    // ============================================================
    // PC register
    // ============================================================
    pc u_pc (
        .clk     (clk),
        .rst     (rst),
        .pc_we   (pc_we && !halt),
        .next_pc (next_pc),
        .pc      (pc_curr)
    );

    assign pc_out = pc_curr;

endmodule