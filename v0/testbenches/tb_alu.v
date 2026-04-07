`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 12/25/2025 12:30:36 AM
// Design Name: 
// Module Name: tb_alu
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


`timescale 1ns/1ps

module tb_alu;

  // Match DUT params
  localparam WORD_W = 8;
  localparam OP_W   = 6;

  // Opcodes (must match your ALU case list)
  localparam OP_ADD   = 6'd0;
  localparam OP_SUB   = 6'd1;
  localparam OP_AND   = 6'd2;
  localparam OP_OR    = 6'd3;
  localparam OP_XOR   = 6'd4;
  localparam OP_NOT   = 6'd5;
  localparam OP_SHL   = 6'd6;
  localparam OP_SHR   = 6'd7;
  localparam OP_SAR   = 6'd8;
  localparam OP_PASSA = 6'd9;
  localparam OP_PASSB = 6'd10;

  // Flags layout (bitfield)
  localparam FLAG_N = 3;
  localparam FLAG_Z = 2;
  localparam FLAG_C = 1;
  localparam FLAG_V = 0;

  // DUT signals
  reg  [WORD_W-1:0] d_in0;
  reg  [WORD_W-1:0] d_in1;
  reg               clk;
  reg  [OP_W-1:0]   op_code;

  wire [WORD_W-1:0] d_out;
  wire [3:0]        flags;

  // Instantiate DUT
  alu #(
    .WORD_W(WORD_W),
    .OP_W(OP_W),
    .FLAG_N(FLAG_N),
    .FLAG_Z(FLAG_Z),
    .FLAG_C(FLAG_C),
    .FLAG_V(FLAG_V)
  ) dut (
    .d_in0(d_in0),
    .d_in1(d_in1),
    .clk(clk),
    .op_code(op_code),
    .d_out(d_out),
    .flags(flags)
  );

  // Clock: 100MHz-ish (10ns period)
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // Compute expected result+flags (matches DUT logic)
  task calc_expected;
    input  [OP_W-1:0]   op;
    input  [WORD_W-1:0] a;
    input  [WORD_W-1:0] b;
    output [WORD_W-1:0] exp_res;
    output [3:0]        exp_flags;

    reg [WORD_W:0] wide;     // 9-bit temp for carry
    reg carry;
    reg overflow;
    reg signed [WORD_W-1:0] s_a, s_b, s_r;
  begin
    exp_res  = {WORD_W{1'b0}};
    carry    = 1'b0;
    overflow = 1'b0;

    s_a = a;
    s_b = b;

    case (op)
      OP_ADD: begin
        wide    = {1'b0, a} + {1'b0, b};
        carry   = wide[WORD_W];
        exp_res = wide[WORD_W-1:0];
        s_r     = exp_res;
        overflow = (~(s_a[WORD_W-1] ^ s_b[WORD_W-1])) &
                    (s_a[WORD_W-1] ^ s_r[WORD_W-1]);
      end

      OP_SUB: begin
        wide    = {1'b0, a} - {1'b0, b};
        carry   = wide[WORD_W];  // same convention as DUT: carry=1 means "no borrow"
        exp_res = wide[WORD_W-1:0];
        s_r     = exp_res;
        overflow = ( (s_a[WORD_W-1] ^ s_b[WORD_W-1])) &
                    (s_a[WORD_W-1] ^ s_r[WORD_W-1]);
      end

      OP_AND:   exp_res = a & b;
      OP_OR:    exp_res = a | b;
      OP_XOR:   exp_res = a ^ b;
      OP_NOT:   exp_res = ~a;
      OP_SHL:   exp_res = a << b[2:0];
      OP_SHR:   exp_res = a >> b[2:0];
      OP_SAR:   exp_res = (s_a >>> b[2:0]);
      OP_PASSA: exp_res = a;
      OP_PASSB: exp_res = b;

      default: begin
        exp_res  = {WORD_W{1'b0}};
        carry    = 1'b0;
        overflow = 1'b0;
      end
    endcase

    // NZCV flags
    exp_flags[FLAG_N] = exp_res[WORD_W-1];
    exp_flags[FLAG_Z] = (exp_res == {WORD_W{1'b0}});
    exp_flags[FLAG_C] = carry;
    exp_flags[FLAG_V] = overflow;
  end
  endtask

  // Apply one test and check after posedge
  task run_test;
    input [OP_W-1:0]   op;
    input [WORD_W-1:0] a;
    input [WORD_W-1:0] b;

    reg [WORD_W-1:0] exp_res;
    reg [3:0]        exp_flags;
  begin
    calc_expected(op, a, b, exp_res, exp_flags);

    // Drive inputs before clock edge
    @(negedge clk);
    op_code = op;
    d_in0   = a;
    d_in1   = b;

    // Wait for the registered output update
    @(posedge clk);
    #1; // small settle for nonblocking assigns

    if (d_out !== exp_res || flags !== exp_flags) begin
      $display("FAIL @%0t  op=%0d  a=0x%0h b=0x%0h | got out=0x%0h flags=%b  exp out=0x%0h flags=%b",
               $time, op, a, b, d_out, flags, exp_res, exp_flags);
      $finish;
    end else begin
      $display("PASS @%0t  op=%0d  a=0x%0h b=0x%0h | out=0x%0h flags=%b",
               $time, op, a, b, d_out, flags);
    end
  end
  endtask

  // Main stimulus
  initial begin
    // init
    d_in0   = 0;
    d_in1   = 0;
    op_code = 0;

    // Let clock run a bit
    repeat (2) @(posedge clk);

    // --- Arithmetic sanity ---
    run_test(OP_ADD, 8'h01, 8'h01); // 2
    run_test(OP_ADD, 8'hFF, 8'h01); // wrap, carry=1, Z=1
    run_test(OP_ADD, 8'h7F, 8'h01); // signed overflow (+127 +1 -> -128), V=1

    run_test(OP_SUB, 8'h05, 8'h03); // 2
    run_test(OP_SUB, 8'h00, 8'h01); // underflow, borrow, carry depends on convention
    run_test(OP_SUB, 8'h80, 8'h01); // -128 -1 -> +127 overflow, V=1

    // --- Logical ---
    run_test(OP_AND, 8'hAA, 8'h0F);
    run_test(OP_OR,  8'hA0, 8'h0F);
    run_test(OP_XOR, 8'hFF, 8'h0F);
    run_test(OP_NOT, 8'h00, 8'h00);

    // --- Shifts ---
    run_test(OP_SHL, 8'h01, 8'h03); // 0x08
    run_test(OP_SHR, 8'h80, 8'h01); // 0x40
    run_test(OP_SAR, 8'h80, 8'h01); // 0xC0 (arith shift keeps sign)

    // --- Pass through ---
    run_test(OP_PASSA, 8'h12, 8'h34);
    run_test(OP_PASSB, 8'h12, 8'h34);

    $display("ALL TESTS PASSED.");
    $finish;
  end

endmodule
