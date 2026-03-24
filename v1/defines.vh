`ifndef RGSONIC32_DEFINES_VH
`define RGSONIC32_DEFINES_VH

// ============================================================
// RG Sonic32 v1 - Global RTL Definitions
// Author: Ryan Gaffere
// File: defines.vh
// ============================================================

// ------------------------------------------------------------
// Global architectural parameters
// ------------------------------------------------------------
`define XLEN                32
`define REG_COUNT           32
`define REG_ADDR_W          5
`define OPCODE_W            6
`define FUNCT6_W            6
`define FUNCT5_W            5
`define IMM16_W             16
`define IMM21_W             21

`define RESET_PC            32'hFFFF_0000
`define TRAP_VECTOR         32'hFFFF_0000

// ------------------------------------------------------------
// Instruction field bit positions
// ------------------------------------------------------------
// Common
`define OPCODE_MSB          31
`define OPCODE_LSB          26

// R-type
`define R_RD_MSB            25
`define R_RD_LSB            21
`define R_RS1_MSB           20
`define R_RS1_LSB           16
`define R_RS2_MSB           15
`define R_RS2_LSB           11
`define R_FUNCT5_MSB        10
`define R_FUNCT5_LSB        6
`define R_FUNCT6_MSB        5
`define R_FUNCT6_LSB        0

// I-type
`define I_RD_MSB            25
`define I_RD_LSB            21
`define I_RS1_MSB           20
`define I_RS1_LSB           16
`define I_IMM16_MSB         15
`define I_IMM16_LSB         0

// S-type
`define S_RS2_MSB           25
`define S_RS2_LSB           21
`define S_RS1_MSB           20
`define S_RS1_LSB           16
`define S_IMM16_MSB         15
`define S_IMM16_LSB         0

// B-type
`define B_RS1_MSB           25
`define B_RS1_LSB           21
`define B_RS2_MSB           20
`define B_RS2_LSB           16
`define B_IMM16_MSB         15
`define B_IMM16_LSB         0

// J-type / U-type
`define J_RD_MSB            25
`define J_RD_LSB            21
`define J_IMM21_MSB         20
`define J_IMM21_LSB         0

`define U_RD_MSB            25
`define U_RD_LSB            21
`define U_IMM21_MSB         20
`define U_IMM21_LSB         0

// ------------------------------------------------------------
// Primary opcode map [31:26]
// Each instruction class has its own opcode to preserve
// the full 16-bit immediate / offset field.
// ------------------------------------------------------------
`define OPC_RTYPE_ALU       6'b000000
`define OPC_ADDI            6'b000001
`define OPC_LB              6'b000110
`define OPC_LBU             6'b000111
`define OPC_LH              6'b001000
`define OPC_LHU             6'b001001
`define OPC_LW              6'b001010
`define OPC_JALR            6'b001011
`define OPC_SB              6'b000010
`define OPC_SH              6'b001100
`define OPC_SW              6'b001101
`define OPC_BRANCH          6'b000011
`define OPC_JUMP            6'b000100
`define OPC_UPPER           6'b000101
`define OPC_SYSTEM          6'b111111

// Legacy aliases (do NOT use in new code)
// `define OPC_ITYPE_MISC   — REMOVED: split into per-instruction opcodes
// `define OPC_STORE        — REMOVED: split into OPC_SB / OPC_SH / OPC_SW

// ------------------------------------------------------------
// R-type funct6 encodings
// ------------------------------------------------------------
`define F6_ADD              6'b000000
`define F6_SUB              6'b000001
`define F6_AND              6'b000010
`define F6_OR               6'b000011
`define F6_XOR              6'b000100
`define F6_SLL              6'b000101
`define F6_SRL              6'b000110
`define F6_SRA              6'b000111
`define F6_CMP              6'b001000
`define F6_TEST             6'b001001
`define F6_MUL              6'b001010
`define F6_MOV              6'b001011

// ------------------------------------------------------------
// I-type sub-ops — REMOVED
// Each I-type instruction now has its own primary opcode.
// No sub-decode needed.
// ------------------------------------------------------------

// ------------------------------------------------------------
// Store sub-ops — REMOVED
// Each store instruction now has its own primary opcode.
// No sub-decode needed.
// ------------------------------------------------------------

// ------------------------------------------------------------
// Branch condition encodings
// NOTE:
// Branches use condition flags architecturally. We still need an RTL
// condition field to distinguish BEQ/BNE/BLT/BGE/BLTU/BGEU.
// For now, use instr[20:18] as a compact internal subdecode.
// ------------------------------------------------------------
`define BR_BEQ              3'b000
`define BR_BNE              3'b001
`define BR_BLT              3'b010
`define BR_BGE              3'b011
`define BR_BLTU             3'b100
`define BR_BGEU             3'b101

// ------------------------------------------------------------
// Jump sub-ops
// For opcode 000100:
//   - J   == JAL with rd = r0
//   - JAL == same encoding class, distinguished by rd != r0
// So we only need a separate code for decoder convenience if desired.
// ------------------------------------------------------------
`define JOP_JAL             1'b0

// ------------------------------------------------------------
// Upper-immediate sub-ops
// ------------------------------------------------------------
`define UOP_LUI             1'b0

// Architecturally suggested shift amount for LUI
`define LUI_SHIFT           16

// ------------------------------------------------------------
// System sub-ops
// Since all system instructions share opcode 111111, define a local
// subdecode on instr[5:0] for clean RTL.
// ------------------------------------------------------------
`define SYS_NOP             6'b000000
`define SYS_HALT            6'b000001
`define SYS_ERET            6'b000010

// ------------------------------------------------------------
// Register roles
// ------------------------------------------------------------
`define REG_ZERO            5'd0
`define REG_RA              5'd1
`define REG_SP              5'd2
`define REG_FP              5'd3

// ------------------------------------------------------------
// Condition flag bit indices
// ------------------------------------------------------------
`define FLAG_Z              0
`define FLAG_N              1
`define FLAG_C              2
`define FLAG_V              3
`define FLAGS_W             4

// ------------------------------------------------------------
// ALU operation encodings
// ------------------------------------------------------------
`define ALU_OP_W            5

`define ALU_ADD             5'd0
`define ALU_SUB             5'd1
`define ALU_AND             5'd2
`define ALU_OR              5'd3
`define ALU_XOR             5'd4
`define ALU_SLL             5'd5
`define ALU_SRL             5'd6
`define ALU_SRA             5'd7
`define ALU_PASS_A          5'd8
`define ALU_PASS_B          5'd9
`define ALU_MUL             5'd10
`define ALU_CMP             5'd11
`define ALU_TEST            5'd12

// ------------------------------------------------------------
// ALU operand select
// ------------------------------------------------------------
`define ALU_ASEL_W          2
`define ALU_ASEL_RS1        2'd0
`define ALU_ASEL_PC         2'd1
`define ALU_ASEL_ZERO       2'd2

`define ALU_BSEL_W          3
`define ALU_BSEL_RS2        3'd0
`define ALU_BSEL_IMM        3'd1
`define ALU_BSEL_CONST4     3'd2
`define ALU_BSEL_UIMM       3'd3

// ------------------------------------------------------------
// Writeback select
// ------------------------------------------------------------
`define WB_SEL_W            2
`define WB_SEL_ALU          2'd0
`define WB_SEL_MEM          2'd1
`define WB_SEL_PC4          2'd2
`define WB_SEL_UIMM         2'd3

// ------------------------------------------------------------
// PC select
// ------------------------------------------------------------
`define PC_SEL_W            3
`define PC_SEL_PC4          3'd0
`define PC_SEL_BRANCH       3'd1
`define PC_SEL_JUMP         3'd2
`define PC_SEL_JALR         3'd3
`define PC_SEL_TRAP         3'd4
`define PC_SEL_EPC          3'd5

// ------------------------------------------------------------
// Memory access size / load extension control
// ------------------------------------------------------------
`define MEM_SIZE_W          2
`define MEM_SIZE_B          2'd0
`define MEM_SIZE_H          2'd1
`define MEM_SIZE_WD         2'd2

`define LOAD_EXT_W          1
`define LOAD_EXT_ZERO       1'b0
`define LOAD_EXT_SIGN       1'b1

// ------------------------------------------------------------
// Trap causes
// Implementation-defined in ISA, but must be consistent.
// These are good v1 local constants.
// ------------------------------------------------------------
`define TRAP_CAUSE_W                32

`define TRAP_CAUSE_ILLEGAL_INSN     32'd1
`define TRAP_CAUSE_MISALIGNED_IF    32'd2
`define TRAP_CAUSE_MISALIGNED_LDST  32'd3
`define TRAP_CAUSE_IFETCH_FAULT     32'd4
`define TRAP_CAUSE_LOAD_FAULT       32'd5
`define TRAP_CAUSE_STORE_FAULT      32'd6
`define TRAP_CAUSE_EXT_IRQ          32'd16

// ------------------------------------------------------------
// STATUS register bits
// ------------------------------------------------------------
`define STATUS_IE           0
`define STATUS_PIE          1

// ------------------------------------------------------------
// Control-unit FSM states
// Multi-cycle reference implementation
// ------------------------------------------------------------
`define FSM_STATE_W         5

`define S_RESET             5'd0
`define S_FETCH             5'd1
`define S_DECODE            5'd2
`define S_EXEC_ALU          5'd3
`define S_EXEC_IMM          5'd4
`define S_EXEC_ADDR         5'd5
`define S_MEM_READ          5'd6
`define S_MEM_WRITE         5'd7
`define S_WRITEBACK         5'd8
`define S_BRANCH            5'd9
`define S_JUMP              5'd10
`define S_TRAP              5'd11
`define S_TRAP_RETURN       5'd12
`define S_HALT              5'd13

`endif