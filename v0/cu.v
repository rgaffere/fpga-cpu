`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Ryan Gaffere
// 
// Create Date: 12/24/2025 11:50:35 PM
// Design Name:
// Module Name: cu
// Project Name: CPU v0
// Target Devices: 
// Tool Versions: 
// Description:
// Control Unit - multi-cycle, hardwired FSM
//
// This CU is intentionally ISA-agnostic: it provides a clean, synthesizable
// fetch/decode/execute skeleton that will be mapped to my eventual instruction format.
//
// Why this shape?
// - mm.v has async read, sync write.
// - alu.v has registered outputs, so ALU results are valid on the
//   next rising edge after I assert the ALU opcode/inputs.
//
//////////////////////////////////////////////////////////////////////////////////

module cu #(
    parameter WORD_W = 8,

    // ---- Instruction field slicing (ISA-dependent; set later) ----
    // By default, we assume an 8-bit instruction where the top 4 bits are opcode.
    parameter OPC_W  = 4,
    parameter OPC_MSB = WORD_W-1,
    parameter OPC_LSB = WORD_W-4
)(
    input  wire              clk,
    input  wire              reset,

    // Current instruction in IR
    input  wire [WORD_W-1:0] ir,

    // Flags from ALU (NZCV). Only needed for conditional branches later.
    input  wire [3:0]        flags,

    // Memory "ready" for future wait-states (tie high for now).
    input  wire              mem_ready,

    // ----------------------------
    // Control outputs (datapath)
    // ----------------------------

    // PC
    output reg               pc_we,
    output reg  [1:0]        pc_next_sel,   // 0: pc+1, 1: branch/jump target, 2: hold (unused), 3: reserved

    // IR
    output reg               ir_we,

    // Memory
    output reg               mem_we,
    output reg               mem_re,         // for symmetry;
    output reg               mem_addr_sel,   // 0: PC (instruction fetch), 1: ALU effective address (data)

    // ALU
    output reg  [5:0]        alu_op,
    output reg  [1:0]        alu_a_sel,      // 0: rs1, 1: PC, 2: zero, 3: reserved
    output reg  [1:0]        alu_b_sel,      // 0: rs2, 1: imm, 2: one, 3: reserved

    // Writeback / regfile (wire to your regfile later)
    output reg               reg_we,
    output reg  [1:0]        wb_sel          // 0: ALU, 1: MEM, 2: PC+1, 3: reserved
);

    // ----------------------------
    // State machine encoding
    // ----------------------------
    localparam S_FETCH  = 3'd0;
    localparam S_DECODE = 3'd1;
    localparam S_EXEC   = 3'd2;
    localparam S_MEM    = 3'd3;
    localparam S_WB     = 3'd4;

    reg [2:0] state, state_n;

    // Extract opcode field (you'll redefine the slice later)
    wire [OPC_W-1:0] opcode = ir[OPC_MSB:OPC_LSB];

    // -------------
    // Defaults
    // -------------
    task automatic defaults;
    begin
        pc_we        = 1'b0;
        pc_next_sel  = 2'd0;

        ir_we        = 1'b0;

        mem_we       = 1'b0;
        mem_re       = 1'b0;
        mem_addr_sel = 1'b0;

        alu_op       = 6'd9;   // PASS A by default
        alu_a_sel    = 2'd0;   // rs1
        alu_b_sel    = 2'd0;   // rs2

        reg_we       = 1'b0;
        wb_sel       = 2'd0;   // ALU
    end
    endtask

    // ----------------------------
    // Next-state logic + outputs
    // ----------------------------
    always @(*) begin
        defaults();
        state_n = state;

        case (state)
            // ----------------------------
            // FETCH
            // - mem_addr_sel=PC
            // - ir_we=1 to latch fetched instruction
            // - pc_we=1 to advance PC (pc+1) (its going to be byte-addressed later)
            // ----------------------------
            S_FETCH: begin
                mem_addr_sel = 1'b0; // PC
                mem_re       = 1'b1;

                // With async read memory, IR can latch same cycle; with real BRAM I might add wait.
                if (mem_ready) begin
                    ir_we = 1'b1;
                    pc_we = 1'b1;
                    pc_next_sel = 2'd0; // pc+1
                    state_n = S_DECODE;
                end else begin
                    state_n = S_FETCH; // wait
                end
            end

            // ----------------------------
            // DECODE
            // - no datapath action required beyond selecting the upcoming path
            // - choose next state based on opcode class
            // ----------------------------
            S_DECODE: begin
                // ISA mapping placeholder:
                //   - ALU reg-reg / reg-imm -> S_EXEC then S_WB
                //   - LOAD/STORE -> S_EXEC (EA) then S_MEM (data) then maybe S_WB
                //   - BRANCH/JUMP -> S_EXEC (pc update) then S_FETCH

                // For now, treat everything as ALU op needing WB.
                state_n = S_EXEC;
            end

            // ----------------------------
            // EXEC
            // - drive ALU operation
            // - for branches/jumps, also write PC here
            // - for load/store, compute effective address
            // ----------------------------
            S_EXEC: begin
                // TODO: fill mapping based on opcode + instruction fields
                // Default behavior: run an ALU op and go to WB
                // (ALU output is registered, so WB occurs next cycle)

                // Example placeholder: map low opcodes directly to your alu.v opcodes
                case (opcode)
                    4'h0: alu_op = 6'd0;  // ADD
                    4'h1: alu_op = 6'd1;  // SUB
                    4'h2: alu_op = 6'd2;  // AND
                    4'h3: alu_op = 6'd3;  // OR
                    4'h4: alu_op = 6'd4;  // XOR
                    4'h5: alu_op = 6'd6;  // SHL
                    4'h6: alu_op = 6'd7;  // SHR
                    4'h7: alu_op = 6'd8;  // SAR
                    default: alu_op = 6'd9; // PASS A
                endcase

                // Default ALU operand sourcing
                alu_a_sel = 2'd0; // rs1
                alu_b_sel = 2'd0; // rs2

                // Next state: WB to commit ALU result
                state_n = S_WB;
            end

            // ----------------------------
            // MEM
            // - perform memory read/write for data access
            // ----------------------------
            S_MEM: begin
                mem_addr_sel = 1'b1; // ALU effective address
                // TODO: choose mem_we/mem_re based on load/store
                // Then either go WB (load) or FETCH (store)
                state_n = S_FETCH;
            end

            // ----------------------------
            // WB
            // - write result back to regfile
            // ----------------------------
            S_WB: begin
                reg_we = 1'b1;
                wb_sel = 2'd0; // ALU by default
                state_n = S_FETCH;
            end

            default: begin
                state_n = S_FETCH;
            end
        endcase
    end

    // ----------------------------
    // State register
    // ----------------------------
    always @(posedge clk) begin
        if (reset)
            state <= S_FETCH;
        else
            state <= state_n;
    end

endmodule
