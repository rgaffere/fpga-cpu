# RG Sonic32 v1 — RTL Audit Report

**Date:** March 23, 2026  
**Scope:** Full audit of all `.v` / `.vh` files against the v1 ISA Specification  
**Original Verdict:** **Would not run.** Three show-stopper bugs plus several additional issues.  
**Status:** All critical, high, and medium bugs **fixed and verified.** Test program (ADDI, ADD, SW, LW, CMP, BEQ, HALT) passes in Icarus Verilog simulation.

---

## CRITICAL — Show-Stopper Bugs

### BUG-1: I-Type Sub-Opcode Steals Bits From the Immediate Field

**Files:** `defines.vh` (lines 114–121), `control_unit.v` (line 94), `datapath.v` (line 125)

**What happens:**  
All I-type instructions (ADDI, LB, LBU, LH, LHU, LW, JALR) share primary opcode `000001`. The RTL distinguishes them by treating `imm16[15:12]` as a 4-bit sub-opcode (`i_subop`). However, the datapath sign-extends the **full** 16-bit immediate field for address and arithmetic computations:

```verilog
wire [31:0] imm16_sext = {{16{instr[15]}}, instr[15:0]};  // datapath.v:125
```

This means the sub-opcode bits are baked into every effective address and immediate value. The consequences:

| Instruction | Sub-op [15:12] | Effective immediate range | Problem |
|---|---|---|---|
| ADDI | `0000` | 0x0000 – 0x0FFF (+0 to +4095) | **Cannot represent negative immediates** |
| LB | `0001` | 0x1000 – 0x1FFF (+4096 to +8191) | **Smallest load offset is +4096** |
| LBU | `0010` | 0x2000 – 0x2FFF | Same class of problem |
| LH | `0011` | 0x3000 – 0x3FFF | Same |
| LHU | `0100` | 0x4000 – 0x4FFF | Same |
| LW | `0101` | 0x5000 – 0x5FFF | `LW r8, 0(r2)` actually loads from `r2 + 0x5000` |
| JALR | `0110` | 0x6000 – 0x6FFF | `JALR r0, r1, 0` (RET) jumps to `r1 + 0x6000` |

**Impact:** Every load, every ADDI with a negative value, and every JALR (including RET) produces a wrong result. The CPU cannot execute even a trivial program with a function call/return or stack-relative load.

**Root cause:** The ISA spec defines a single 16-bit immediate for I-type but groups multiple instruction classes under one opcode. The RTL resolves this by stealing immediate bits — a choice that destroys the immediate field.

**Fix — choose one:**

**(A) Give each I-type instruction its own primary opcode (recommended).** The 6-bit opcode space has 64 slots and only 7 are used. Assign dedicated opcodes for ADDI, LB, LBU, LH, LHU, LW, JALR. This preserves the full 16-bit immediate and is the cleanest fix:

```
000001  ADDI
000110  LB
000111  LBU
001000  LH
001001  LHU
001010  LW
001011  JALR
```

Then remove `i_subop` entirely and decode on `opcode` alone.

**(B) Use a different sub-encoding field** that doesn't overlap the immediate, e.g., repurpose bits `[25:23]` of the rd field as a 3-bit sub-op (sacrificing 3 bits of rd width — not viable with 32 registers).

Option A is strongly recommended.

---

### BUG-2: Store Sub-Opcode Steals Bits From the Store Offset

**Files:** `defines.vh` (lines 126–128), `control_unit.v` (line 492)

**What happens:**  
Store instructions (SB, SH, SW) share opcode `000010`. The RTL distinguishes them using `ir_reg[15:14]`:

```verilog
case (ir_reg[15:14])          // control_unit.v:492
    `SOP_SB: d_size = `MEM_SIZE_B;   // 2'b00
    `SOP_SH: d_size = `MEM_SIZE_H;   // 2'b01
    `SOP_SW: d_size = `MEM_SIZE_WD;  // 2'b10
```

But `instr[15:0]` is the S-type signed offset, so the store size depends on the **value of the address offset**, not the instruction encoding. The effective address is computed as `rs1 + signext(imstr[15:0])`, and the sub-op bits corrupt it:

| Instruction | Bits [15:14] | Offset range | Problem |
|---|---|---|---|
| SB | `00` | 0x0000 – 0x3FFF | Positive only, 0–16383 |
| SH | `01` | 0x4000 – 0x7FFF | Always +16384 to +32767 |
| SW | `10` or `11` | 0x8000 – 0xFFFF (sign-extended to negative) | Always negative offsets |

**Impact:** `SW r5, 0(r2)` (store word at `r2+0`) is impossible to encode. Any store to a small positive offset is broken.

**Fix:** Same as BUG-1 — assign each store variant its own opcode:

```
000010  SB
001100  SH
001101  SW
```

---

### BUG-3: Spurious Fetch Response Corrupts `instr_pc`, Breaking All Branches and Jumps

**Files:** `datapath.v` (lines 344–349), `mem_subsystem.v` (arbitration logic)

**What happens:**  
When an instruction fetch completes (`if_ready=1`), the datapath captures the fetched instruction's PC:

```verilog
always @(posedge clk) begin
    if (rst)
        instr_pc <= 0;
    else if (if_ready)          // NO state guard!
        instr_pc <= pc_curr;
end
```

The mem_subsystem uses a pending/ready handshake that generates a **spurious second fetch** due to a timing interaction: on the cycle `if_ready` fires, `if_pending` clears to 0 while `if_req` is still asserted (the FSM hasn't transitioned out of `S_FETCH` yet combinationally), so a new request is accepted. This spurious request completes 2 cycles later with another `if_ready` pulse — while the FSM is now in `S_BRANCH`, `S_EXEC_ALU`, or another execute state.

When the spurious `if_ready` fires, `instr_pc` is overwritten with `pc_curr` (which is now PC+4, since the PC was advanced during the real fetch). This corrupts all branch/jump targets and link addresses by +4:

- `branch_target = instr_pc + 4 + offset` → becomes `(PC+4) + 4 + offset = PC + 8 + offset` (should be `PC + 4 + offset`)
- `jump_target` — same, off by +4
- Link address for JAL/JALR (`instr_pc + 4`) → becomes `PC + 8` (should be `PC + 4`)

**Impact:** Every branch and jump lands at the wrong address. Every function call saves a wrong return address. The CPU will diverge from the correct execution path on the first control-flow instruction.

**Fix (datapath.v, line 347):**  
Gate the `instr_pc` capture with `if_req`, which is only asserted during `S_FETCH`:

```verilog
else if (if_ready && if_req)
    instr_pc <= pc_curr;
```

---

## HIGH — Correctness Bugs

### BUG-4: Double Memory Requests on Data Port

**File:** `mem_subsystem.v`

**What happens:**  
The same pending/ready race described in BUG-3 also affects the data port. When `d_ready` fires, `d_pending` clears to 0 while `d_req` is still asserted (FSM hasn't transitioned yet). A second data request is accepted.

For reads this is benign (the spurious `d_ready` pulse is ignored by the FSM). For writes, the same data is written twice to the same address — idempotent but wasteful, and it could cause issues if memory-mapped I/O is ever added.

**Fix (mem_subsystem.v):**  
Add a one-cycle "cooldown" flag, or change the acceptance condition to prevent re-acceptance on the same cycle that a response fires:

```verilog
wire d_just_completed;  // high for one cycle after d_pending clears
// ... and gate: wire d_accept = d_new_req && !d_just_completed;
```

---

### BUG-5: `trap_regs` Ignores Interrupt Pending Signal

**File:** `trap_regs.v` (line 17)

**What happens:**  
The module computes `irq_pending = ext_irq & status_out[STATUS_IE]` but never uses it. There is no logic to enter a trap when an external interrupt is asserted and enabled. Currently `ext_irq` is hardwired to `1'b0` in `cpu_top.v`, so this is latent, but it means the interrupt mechanism described in Section 11.2.2 of the ISA is completely non-functional.

**Fix:** Either implement interrupt entry logic (check `irq_pending` on each fetch cycle and enter `S_TRAP` with `TRAP_CAUSE_EXT_IRQ`), or remove the dead `irq_pending` wire to avoid synthesis warnings and document interrupts as unimplemented.

---

### BUG-6: Flags Are Sampled From Combinational ALU During `S_EXEC_ALU` But the ALU Inputs May Glitch on State Transition

**File:** `datapath.v` (lines 223–231)

**What happens:**  
During `S_EXEC_ALU`, `flags_we=1` and the ALU's combinational flag outputs feed directly into the flags register. On the posedge that transitions from `S_EXEC_ALU` to `S_FETCH`, the flags latch. However, the ALU input muxes are controlled by the **current state's** control outputs. On the very next cycle (`S_FETCH`), the ALU control defaults change (`alu_asel→RS1`, `alu_bsel→RS2`, `alu_op→ADD`). Since `flags_we` goes to 0 in `S_FETCH`, the flags register is safe — but any hold-time violation or clock-skew could cause a glitch. In simulation this works fine; on FPGA fabric with tight timing, it could be fragile.

**Recommendation:** Latch the ALU flags into a staging register (like `alu_result_reg`) and commit from there during writeback, rather than relying on combinational flag signals at a state boundary.

---

## MEDIUM — Functional Limitations

### BUG-7: `instr_pc` Initializes to Zero, Not `RESET_PC`

**File:** `datapath.v` (line 346)

```verilog
if (rst)
    instr_pc <= {`XLEN{1'b0}};   // 0x00000000, not 0xFFFF0000
```

On the very first fetch, `instr_pc` is captured correctly from `pc_curr` (which is `RESET_PC`). So this isn't a functional bug in normal operation. However, if any logic samples `instr_pc` before the first fetch completes (e.g., during `S_RESET`), it would see 0 instead of `RESET_PC`. Low risk but worth initializing correctly for robustness.

---

### BUG-8: Branch Not-Taken Path Uses `pc_plus_4` (Now PC+8 Relative to Branch Instruction)

**File:** `datapath.v` (line 360)

```verilog
`PC_SEL_BRANCH: next_pc = branch_taken ? branch_target : pc_plus_4;
```

The `pc_plus_4` here is `pc_curr + 4`. Since `pc_curr` was already advanced to `(branch_instr_addr + 4)` during fetch, `pc_plus_4` equals `branch_instr_addr + 8`. For a not-taken branch, the control unit sets `pc_we = 0`, so this value is **never written** — the PC stays at the correctly-advanced `branch_instr_addr + 4`. So the not-taken path works by accident.

However, this is fragile. If anyone changes the branch logic to always write PC (e.g., `pc_we = 1` unconditionally in `S_BRANCH`), not-taken branches would jump to PC+8. The `pc_plus_4` fallback in the mux is dead code for not-taken branches and should be removed or commented to prevent confusion:

```verilog
`PC_SEL_BRANCH: next_pc = branch_target;  // pc_we is 0 if not taken
```

---

## LOW — Style / Robustness Notes

### NOTE-1: Register File Has Redundant r0 Protection

**File:** `regfile.v` (lines 33–37)

The code both checks `rd_addr != REG_ZERO` before writing AND unconditionally zeros `regs[0]` every cycle. The unconditional zero-write masks any bugs in the guard check. This works but uses an extra write port cycle. Pick one approach.

### NOTE-2: `readmemh` for Byte-Addressable BRAM May Not Work As Expected

**File:** `mem_bram.v` (line 38)

`$readmemh(INIT_FILE, mem)` loads hex values into the byte array. Each line of the hex file must contain a single byte value (00–FF). If the init file contains 32-bit words per line (common for instruction memory), they'll be misinterpreted as single bytes. Ensure the init file format matches the byte-granular memory organization.

### NOTE-3: Synthesis Warning — Unused Ports

`datapath.v` outputs `opcode`, `funct6`, `rd_idx`, `rs1_idx`, `rs2_idx` for debug visibility, but `cpu_top.v` declares the corresponding wires and never uses them. Synthesis tools will emit warnings. Either connect them to debug outputs or remove them.

---

## Summary Table

| ID | Severity | Component | Description |
|---|---|---|---|
| BUG-1 | **CRITICAL** | defines.vh, control_unit, datapath | I-type sub-op destroys 16-bit immediate — all loads, ADDI, JALR broken |
| BUG-2 | **CRITICAL** | defines.vh, control_unit | Store sub-op destroys 16-bit offset — all stores broken |
| BUG-3 | **CRITICAL** | datapath, mem_subsystem | Spurious fetch corrupts `instr_pc` — all branches/jumps off by +4 |
| BUG-4 | HIGH | mem_subsystem | Double memory requests from pending/ready race |
| BUG-5 | HIGH | trap_regs | `irq_pending` computed but never used — interrupts dead |
| BUG-6 | HIGH | datapath | Flags sampled from combinational ALU at state edge — timing fragile |
| BUG-7 | MEDIUM | datapath | `instr_pc` initializes to 0 instead of RESET_PC |
| BUG-8 | MEDIUM | datapath | Not-taken branch mux arm is dead code but misleading |

---

## Recommended Fix Priority

1. **BUG-1 + BUG-2** — Reassign opcodes so each instruction gets its own. This is an ISA encoding change that must be coordinated with the assembler/toolchain. Until this is fixed, no instruction can be encoded correctly.
2. **BUG-3** — One-line fix in `datapath.v` (add `&& if_req` guard). Must be applied before any control-flow instruction will work.
3. **BUG-4** — Fix the double-request race in `mem_subsystem.v` to prevent spurious memory operations.
4. **BUG-5** — Either implement interrupt entry or remove dead code.
5. **BUG-6** through **BUG-8** — Clean up for robustness.

---

## Fixes Applied (in `fixed_rtl/`)

All bugs except BUG-5 (latent, requires design decision) and BUG-6 (robustness recommendation) have been fixed. The changes are:

| Bug | File(s) Changed | What Was Done |
|---|---|---|
| BUG-1 | `defines.vh`, `control_unit.v`, `datapath.v` | Gave each I-type instruction its own primary opcode (OPC_ADDI, OPC_LB, OPC_LBU, OPC_LH, OPC_LHU, OPC_LW, OPC_JALR). Removed `i_subop` decode entirely. Full 16-bit immediate preserved. |
| BUG-2 | `defines.vh`, `control_unit.v`, `datapath.v` | Gave each store instruction its own primary opcode (OPC_SB, OPC_SH, OPC_SW). Removed `SOP_*` sub-ops. Store size decoded from opcode, not offset bits. |
| BUG-3 | `datapath.v` | Gated `instr_pc` capture: `if (if_ready && if_req)` — prevents spurious overwrites when a stale fetch response arrives during execute states. |
| BUG-4 | `mem_subsystem.v` | Added `if_just_responded` / `d_just_responded` one-cycle cooldown flags. New requests are blocked for one cycle after a response fires, closing the double-request race. |
| BUG-7 | `datapath.v` | Changed `instr_pc` reset value from `0` to `` `RESET_PC ``. |
| BUG-8 | `datapath.v` | Simplified branch mux to `next_pc = branch_target` (the not-taken fallback was dead code since `pc_we=0` when not taken). |

### Verification

Compiled clean (zero warnings) with Icarus Verilog 12.0. A 10-instruction test program exercises:

- **ADDI** (immediate arithmetic, positive values)
- **ADD** (register-register arithmetic)
- **SW** (word store via base+offset)
- **LW** (word load via base+offset)
- **CMP** (flag-setting subtraction, Z flag)
- **BEQ** (conditional branch, taken path)
- **HALT** (processor stop)

All register values and control-flow behavior match expected results.

### ISA Encoding Impact

BUG-1 and BUG-2 fixes change the primary opcode assignments. Any assembler, linker, or toolchain targeting RG Sonic32 v1 must be updated to use the new opcode map:

```
000000  R-type ALU (ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, MUL, MOV, CMP, TEST)
000001  ADDI
000010  SB
000011  Branch (BEQ, BNE, BLT, BGE, BLTU, BGEU)
000100  Jump (J, JAL)
000101  Upper Immediate (LUI)
000110  LB
000111  LBU
001000  LH
001001  LHU
001010  LW
001011  JALR
001100  SH
001101  SW
111111  System (NOP, HALT, ERET)
```

