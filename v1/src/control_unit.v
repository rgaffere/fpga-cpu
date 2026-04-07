`timescale 1ns / 1ps
`include "defines.vh"

module control_unit (
    input  wire                     clk,
    input  wire                     rst,

    // ============================================================
    // Inputs from datapath / memory side
    // ============================================================
    input  wire [`XLEN-1:0]         fetched_instr,
    input  wire                     if_ready,
    input  wire                     if_fault,
    input  wire                     if_misaligned,

    input  wire                     d_ready,
    input  wire                     d_fault,
    input  wire                     d_misaligned,

    input  wire                     flag_z,
    input  wire                     flag_n,
    input  wire                     flag_c,
    input  wire                     flag_v,

    // Trap return support
    input  wire [`XLEN-1:0]         epc_in,

    // ============================================================
    // Outputs to datapath
    // ============================================================
    output wire [`XLEN-1:0]         instr,

    output reg                      pc_we,
    output reg  [`PC_SEL_W-1:0]     pc_sel,

    output reg  [`ALU_ASEL_W-1:0]   alu_asel,
    output reg  [`ALU_BSEL_W-1:0]   alu_bsel,
    output reg  [`ALU_OP_W-1:0]     alu_op,

    output reg                      rd_we,
    output reg  [`WB_SEL_W-1:0]     wb_sel,

    output reg                      flags_we,

    output reg                      d_req,
    output reg                      d_we,
    output reg  [`MEM_SIZE_W-1:0]   d_size,
    output reg                      load_ext_sel,

    output reg                      if_req,
    output reg                      branch_taken,
    output reg                      halt,

    // ============================================================
    // Optional trap hooks for trap_regs / cpu_top
    // ============================================================
    output reg                      trap_enter,
    output reg  [`TRAP_CAUSE_W-1:0] trap_cause,
    output reg                      alu_latch,

    // ============================================================
    // Debug / visibility
    // ============================================================
    output wire [`FSM_STATE_W-1:0]  state_out
);

    // ------------------------------------------------------------
    // Instruction Register (IR)
    // control_unit owns IR per repo structure
    // ------------------------------------------------------------
    reg [`XLEN-1:0] ir_reg;
    assign instr = ir_reg;

    // ------------------------------------------------------------
    // State register
    // ------------------------------------------------------------
    reg [`FSM_STATE_W-1:0] state, next_state;
    assign state_out = state;

    reg [`TRAP_CAUSE_W-1:0] trap_cause_reg, trap_cause_next;

    // ------------------------------------------------------------
    // Useful decoded fields from IR
    // ------------------------------------------------------------
    wire [5:0] opcode = ir_reg[`OPCODE_MSB:`OPCODE_LSB];
    wire [5:0] funct6 = ir_reg[`R_FUNCT6_MSB:`R_FUNCT6_LSB];

    wire [`REG_ADDR_W-1:0] r_rd = ir_reg[`R_RD_MSB:`R_RD_LSB];
    wire [`REG_ADDR_W-1:0] i_rd = ir_reg[`I_RD_MSB:`I_RD_LSB];
    wire [`REG_ADDR_W-1:0] j_rd = ir_reg[`J_RD_MSB:`J_RD_LSB];
    wire [`REG_ADDR_W-1:0] u_rd = ir_reg[`U_RD_MSB:`U_RD_LSB];

    // Branch condition from B-type [20:18]
    wire [2:0] br_cond = ir_reg[20:18];

    wire rtype_has_rd = (r_rd != `REG_ZERO);
    wire itype_has_rd = (i_rd != `REG_ZERO);
    wire jtype_has_rd = (j_rd != `REG_ZERO);
    wire utype_has_rd = (u_rd != `REG_ZERO);

    // ------------------------------------------------------------
    // Helper: is this a load opcode?
    // ------------------------------------------------------------
    wire is_load = (opcode == `OPC_LB)  || (opcode == `OPC_LBU) ||
                   (opcode == `OPC_LH)  || (opcode == `OPC_LHU) ||
                   (opcode == `OPC_LW);

    // Helper: is this a store opcode?
    wire is_store = (opcode == `OPC_SB) || (opcode == `OPC_SH) ||
                    (opcode == `OPC_SW);

    // ------------------------------------------------------------
    // Decode validity helpers
    // ------------------------------------------------------------
    wire valid_r_funct6 =
        (funct6 == `F6_ADD)  ||
        (funct6 == `F6_SUB)  ||
        (funct6 == `F6_AND)  ||
        (funct6 == `F6_OR)   ||
        (funct6 == `F6_XOR)  ||
        (funct6 == `F6_SLL)  ||
        (funct6 == `F6_SRL)  ||
        (funct6 == `F6_SRA)  ||
        (funct6 == `F6_MUL)  ||
        (funct6 == `F6_MOV)  ||
        (funct6 == `F6_CMP)  ||
        (funct6 == `F6_TEST);

    wire valid_sys_funct6 =
        (funct6 == `SYS_NOP)  ||
        (funct6 == `SYS_HALT) ||
        (funct6 == `SYS_ERET);

    wire valid_opcode =
        (opcode == `OPC_RTYPE_ALU) ||
        (opcode == `OPC_ADDI)      ||
        is_load                     ||
        is_store                    ||
        (opcode == `OPC_JALR)      ||
        (opcode == `OPC_BRANCH)    ||
        (opcode == `OPC_JUMP)      ||
        (opcode == `OPC_UPPER)     ||
        (opcode == `OPC_SYSTEM);

    wire illegal_decode =
        !valid_opcode ||
        ((opcode == `OPC_RTYPE_ALU) && !valid_r_funct6) ||
        ((opcode == `OPC_SYSTEM)    && !valid_sys_funct6);

    // ------------------------------------------------------------
    // Branch condition evaluation from architectural flags
    // ISA says branches use current flags only.
    // ------------------------------------------------------------
    wire branch_cond_true =
        (br_cond == `BR_BEQ)  ?  flag_z :
        (br_cond == `BR_BNE)  ? ~flag_z :
        (br_cond == `BR_BLT)  ? (flag_n ^ flag_v) :
        (br_cond == `BR_BGE)  ? ~(flag_n ^ flag_v) :
        (br_cond == `BR_BLTU) ? ~flag_c :
        (br_cond == `BR_BGEU) ?  flag_c :
                                1'b0;

    // ------------------------------------------------------------
    // State register + IR update
    // ------------------------------------------------------------
    always @(posedge clk) begin
        if (rst) begin
            state          <= `S_RESET;
            ir_reg         <= {`XLEN{1'b0}};
            trap_cause_reg <= {`TRAP_CAUSE_W{1'b0}};
        end else begin
            state          <= next_state;
            trap_cause_reg <= trap_cause_next;

            if (state == `S_FETCH && if_ready && !if_fault)
                ir_reg <= fetched_instr;
        end
    end

    // ------------------------------------------------------------
    // Next-state logic
    // ------------------------------------------------------------
    always @(*) begin
        next_state = state;

        case (state)
            `S_RESET: begin
                next_state = `S_FETCH;
            end

            `S_FETCH: begin
                if (if_fault)
                    next_state = `S_TRAP;
                else if (if_ready)
                    next_state = `S_DECODE;
                else
                    next_state = `S_FETCH;
            end

            `S_DECODE: begin
                if (illegal_decode) begin
                    next_state = `S_TRAP;
                end else begin
                    case (opcode)
                        `OPC_RTYPE_ALU: begin
                            next_state = `S_EXEC_ALU;
                        end

                        `OPC_ADDI: begin
                            next_state = `S_EXEC_IMM;
                        end

                        `OPC_LB,
                        `OPC_LBU,
                        `OPC_LH,
                        `OPC_LHU,
                        `OPC_LW: begin
                            next_state = `S_EXEC_ADDR;
                        end

                        `OPC_JALR: begin
                            next_state = `S_JUMP;
                        end

                        `OPC_SB,
                        `OPC_SH,
                        `OPC_SW: begin
                            next_state = `S_EXEC_ADDR;
                        end

                        `OPC_BRANCH: begin
                            next_state = `S_BRANCH;
                        end

                        `OPC_JUMP: begin
                            next_state = `S_JUMP;
                        end

                        `OPC_UPPER: begin
                            next_state = `S_EXEC_IMM;
                        end

                        `OPC_SYSTEM: begin
                            case (funct6)
                                `SYS_NOP:  next_state = `S_FETCH;
                                `SYS_HALT: next_state = `S_HALT;
                                `SYS_ERET: next_state = `S_TRAP_RETURN;
                                default:   next_state = `S_TRAP;
                            endcase
                        end

                        default: begin
                            next_state = `S_TRAP;
                        end
                    endcase
                end
            end

            `S_EXEC_ALU: begin
                if ((funct6 == `F6_CMP) || (funct6 == `F6_TEST))
                    next_state = `S_FETCH;
                else
                    next_state = `S_WRITEBACK;
            end

            `S_EXEC_IMM: begin
                next_state = `S_WRITEBACK;
            end

            `S_EXEC_ADDR: begin
                if (is_store)
                    next_state = `S_MEM_WRITE;
                else
                    next_state = `S_MEM_READ;
            end

            `S_MEM_READ: begin
                if (d_fault)
                    next_state = `S_TRAP;
                else if (d_ready)
                    next_state = `S_WRITEBACK;
                else
                    next_state = `S_MEM_READ;
            end

            `S_MEM_WRITE: begin
                if (d_fault)
                    next_state = `S_TRAP;
                else if (d_ready)
                    next_state = `S_FETCH;
                else
                    next_state = `S_MEM_WRITE;
            end

            `S_WRITEBACK: begin
                next_state = `S_FETCH;
            end

            `S_BRANCH: begin
                next_state = `S_FETCH;
            end

            `S_JUMP: begin
                next_state = `S_FETCH;
            end

            `S_TRAP: begin
                next_state = `S_FETCH;
            end

            `S_TRAP_RETURN: begin
                next_state = `S_FETCH;
            end

            `S_HALT: begin
                next_state = `S_HALT;
            end

            default: begin
                next_state = `S_TRAP;
            end
        endcase
    end

    // ------------------------------------------------------------
    // Control-output logic
    // ------------------------------------------------------------
    always @(*) begin
        trap_cause_next = trap_cause_reg;

        pc_we        = 1'b0;
        pc_sel       = `PC_SEL_PC4;

        alu_asel     = `ALU_ASEL_RS1;
        alu_bsel     = `ALU_BSEL_RS2;
        alu_op       = `ALU_ADD;

        rd_we        = 1'b0;
        wb_sel       = `WB_SEL_ALU;

        flags_we     = 1'b0;

        d_req        = 1'b0;
        d_we         = 1'b0;
        d_size       = `MEM_SIZE_WD;
        load_ext_sel = `LOAD_EXT_ZERO;

        if_req       = 1'b0;
        branch_taken = 1'b0;
        halt         = 1'b0;

        trap_enter   = 1'b0;
        trap_cause   = {`TRAP_CAUSE_W{1'b0}};

        alu_latch    = 1'b0;

        case (state)
            // ----------------------------------------
            // RESET
            // ----------------------------------------
            `S_RESET: begin
            end

            // ----------------------------------------
            // FETCH
            // ----------------------------------------
            `S_FETCH: begin
                if_req = 1'b1;
                pc_sel = `PC_SEL_PC4;

                if (if_fault) begin
                    if (if_misaligned)
                        trap_cause_next = `TRAP_CAUSE_MISALIGNED_IF;
                    else
                        trap_cause_next = `TRAP_CAUSE_IFETCH_FAULT;
                end else if (if_ready) begin
                    pc_we = 1'b1;
                end
            end

            // ----------------------------------------
            // DECODE
            // ----------------------------------------
            `S_DECODE: begin
                if (illegal_decode) begin
                    trap_cause_next = `TRAP_CAUSE_ILLEGAL_INSN;
                end
            end

            // ----------------------------------------
            // EXEC_ALU
            // ----------------------------------------
            `S_EXEC_ALU: begin
                alu_asel  = `ALU_ASEL_RS1;
                alu_bsel  = `ALU_BSEL_RS2;
                alu_latch = 1'b1;

                case (funct6)
                    `F6_ADD:  alu_op = `ALU_ADD;
                    `F6_SUB:  alu_op = `ALU_SUB;
                    `F6_AND:  alu_op = `ALU_AND;
                    `F6_OR:   alu_op = `ALU_OR;
                    `F6_XOR:  alu_op = `ALU_XOR;
                    `F6_SLL:  alu_op = `ALU_SLL;
                    `F6_SRL:  alu_op = `ALU_SRL;
                    `F6_SRA:  alu_op = `ALU_SRA;
                    `F6_MUL:  alu_op = `ALU_MUL;
                    `F6_MOV:  alu_op = `ALU_PASS_A;
                    `F6_CMP:  alu_op = `ALU_CMP;
                    `F6_TEST: alu_op = `ALU_TEST;
                    default:  alu_op = `ALU_ADD;
                endcase

                if ((funct6 == `F6_CMP) || (funct6 == `F6_TEST))
                    flags_we = 1'b1;
            end

            // ----------------------------------------
            // EXEC_IMM
            // ----------------------------------------
            `S_EXEC_IMM: begin
                if (opcode == `OPC_UPPER) begin
                    // LUI writes upper immediate directly; no ALU latch needed
                    wb_sel = `WB_SEL_UIMM;
                end else begin
                    // ADDI
                    alu_asel  = `ALU_ASEL_RS1;
                    alu_bsel  = `ALU_BSEL_IMM;
                    alu_op    = `ALU_ADD;
                    wb_sel    = `WB_SEL_ALU;
                    alu_latch = 1'b1;
                end
            end

            // ----------------------------------------
            // EXEC_ADDR
            // ----------------------------------------
            `S_EXEC_ADDR: begin
                alu_asel  = `ALU_ASEL_RS1;
                alu_bsel  = `ALU_BSEL_IMM;
                alu_op    = `ALU_ADD;
                alu_latch = 1'b1;
            end

            // ----------------------------------------
            // MEM_READ
            // ----------------------------------------
            `S_MEM_READ: begin
                d_req = 1'b1;
                d_we  = 1'b0;

                case (opcode)
                    `OPC_LB: begin
                        d_size       = `MEM_SIZE_B;
                        load_ext_sel = `LOAD_EXT_SIGN;
                    end

                    `OPC_LBU: begin
                        d_size       = `MEM_SIZE_B;
                        load_ext_sel = `LOAD_EXT_ZERO;
                    end

                    `OPC_LH: begin
                        d_size       = `MEM_SIZE_H;
                        load_ext_sel = `LOAD_EXT_SIGN;
                    end

                    `OPC_LHU: begin
                        d_size       = `MEM_SIZE_H;
                        load_ext_sel = `LOAD_EXT_ZERO;
                    end

                    `OPC_LW: begin
                        d_size       = `MEM_SIZE_WD;
                        load_ext_sel = `LOAD_EXT_ZERO;
                    end

                    default: begin
                        d_size       = `MEM_SIZE_WD;
                        load_ext_sel = `LOAD_EXT_ZERO;
                    end
                endcase

                if (d_fault) begin
                    if (d_misaligned)
                        trap_cause_next = `TRAP_CAUSE_MISALIGNED_LDST;
                    else
                        trap_cause_next = `TRAP_CAUSE_LOAD_FAULT;
                end
            end

            // ----------------------------------------
            // MEM_WRITE
            // ----------------------------------------
            `S_MEM_WRITE: begin
                d_req = 1'b1;
                d_we  = 1'b1;

                case (opcode)
                    `OPC_SB: d_size = `MEM_SIZE_B;
                    `OPC_SH: d_size = `MEM_SIZE_H;
                    `OPC_SW: d_size = `MEM_SIZE_WD;
                    default: d_size = `MEM_SIZE_WD;
                endcase

                if (d_fault) begin
                    if (d_misaligned)
                        trap_cause_next = `TRAP_CAUSE_MISALIGNED_LDST;
                    else
                        trap_cause_next = `TRAP_CAUSE_STORE_FAULT;
                end
            end

            // ----------------------------------------
            // WRITEBACK
            // ----------------------------------------
            `S_WRITEBACK: begin
                case (opcode)
                    `OPC_RTYPE_ALU: begin
                        if (rtype_has_rd && (funct6 != `F6_CMP) && (funct6 != `F6_TEST)) begin
                            rd_we  = 1'b1;
                            wb_sel = `WB_SEL_ALU;
                        end
                    end

                    `OPC_ADDI: begin
                        if (itype_has_rd) begin
                            rd_we  = 1'b1;
                            wb_sel = `WB_SEL_ALU;
                        end
                    end
					`OPC_LB: begin
						if (itype_has_rd) begin
							rd_we        = 1'b1;
							wb_sel       = `WB_SEL_MEM;
							d_size       = `MEM_SIZE_B;
							load_ext_sel = `LOAD_EXT_SIGN;
						end
					end
					`OPC_LBU: begin
						if (itype_has_rd) begin
							rd_we        = 1'b1;
							wb_sel       = `WB_SEL_MEM;
							d_size       = `MEM_SIZE_B;
							load_ext_sel = `LOAD_EXT_ZERO;
						end
					end
					`OPC_LH: begin
						if (itype_has_rd) begin
							rd_we        = 1'b1;
							wb_sel       = `WB_SEL_MEM;
							d_size       = `MEM_SIZE_H;
							load_ext_sel = `LOAD_EXT_SIGN;
						end
					end
					`OPC_LHU: begin
						if (itype_has_rd) begin
							rd_we        = 1'b1;
							wb_sel       = `WB_SEL_MEM;
							d_size       = `MEM_SIZE_H;
							load_ext_sel = `LOAD_EXT_ZERO;
						end
					end
                    `OPC_LW: begin
                        if (itype_has_rd) begin
                            rd_we  = 1'b1;
                            wb_sel = `WB_SEL_MEM;
                        end
                    end

                    `OPC_UPPER: begin
                        if (utype_has_rd) begin
                            rd_we  = 1'b1;
                            wb_sel = `WB_SEL_UIMM;
                        end
                    end

                    default: begin
                    end
                endcase
            end

            // ----------------------------------------
            // BRANCH
            // ----------------------------------------
            `S_BRANCH: begin
                pc_sel       = `PC_SEL_BRANCH;
                branch_taken = branch_cond_true;
                pc_we        = branch_cond_true;
            end

            // ----------------------------------------
            // JUMP
            // ----------------------------------------
            `S_JUMP: begin
                if (opcode == `OPC_JALR) begin
                    pc_sel = `PC_SEL_JALR;
                    if (itype_has_rd) begin
                        rd_we  = 1'b1;
                        wb_sel = `WB_SEL_PC4;
                    end
                end else begin
                    pc_sel = `PC_SEL_JUMP;
                    if (jtype_has_rd) begin
                        rd_we  = 1'b1;
                        wb_sel = `WB_SEL_PC4;
                    end
                end

                pc_we = 1'b1;
            end

            // ----------------------------------------
            // TRAP
            // ----------------------------------------
            `S_TRAP: begin
                trap_enter = 1'b1;
                pc_sel     = `PC_SEL_TRAP;
                pc_we      = 1'b1;
                trap_cause = trap_cause_reg;
            end

            // ----------------------------------------
            // TRAP_RETURN
            // ----------------------------------------
            `S_TRAP_RETURN: begin
                pc_sel = `PC_SEL_EPC;
                pc_we  = 1'b1;
            end

            // ----------------------------------------
            // HALT
            // ----------------------------------------
            `S_HALT: begin
                halt = 1'b1;
            end

            default: begin
                trap_cause_next = `TRAP_CAUSE_ILLEGAL_INSN;
            end
        endcase
    end

endmodule
