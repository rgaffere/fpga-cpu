# Execution Trace Walkthrough – Smoke Test Program

## Overview

This document provides a step-by-step walkthrough of a simple smoke test program executed on the RG Sonic32 CPU v1 using the hardware debug and observability tooling. The goal is to demonstrate correct instruction execution, data movement, and final architectural state by correlating expected behavior with observed execution traces.

---

## Program Behavior

The smoke test performs the following operations:

1. Load immediate value `0x0A` into register `r4`
2. Load immediate value `0x14` into register `r5`
3. Add `r4 + r5` and store the result in `r6`
4. Load immediate value `0x100` into register `r7`
5. Store the value of `r6` to memory address `0x00000000`
6. Move the stored value into register `r8`
7. Halt execution and dump register state

Expected result:

- `r6 = 0x1E` (10 + 20)
- `MEM[0x00000000] = 0x1E`
- `r8 = 0x1E`

---

## Execution Trace

```text
PC=FFFF0000 IR=0480000A RD=04 WB=0000000A
PC=FFFF0004 IR=04A00014 RD=05 WB=00000014
PC=FFFF0008 IR=00C42800 RD=06 WB=0000001E
PC=FFFF000C IR=04E00100 RD=07 WB=00000100
PC=FFFF0010 IR=34C70000 ST A=00000000 D=0000001E
PC=FFFF0014 IR=29070000 RD=08 WB=0000001E
HALT
r00=00000000
r01=00000000
r02=00000000
r03=00000000
r04=0000000A
r05=00000014
r06=0000001E
r07=00000100
r08=0000001E
r09=00000000
r10=00000000
r11=00000000
r12=00000000
r13=00000000
r14=00000000
r15=00000000
r16=00000000
r17=00000000
r18=00000000
r19=00000000
r20=00000000
r21=00000000
r22=00000000
r23=00000000
r24=00000000
r25=00000000
r26=00000000
r27=00000000
r28=00000000
r29=00000000
r30=00000000
r31=00000000
```

### 1. Load Immediate → r4

```text
PC=FFFF0000 IR=0480000A RD=04 WB=0000000A
```

- Loads `0x0A` into `r4`
- Result: `r4 = 0x0A`

### 2. Load Immediate → r5

```text
PC=FFFF0004 IR=04A00014 RD=05 WB=00000014
```

- Loads `0x14` into `r5`
- Result: `r5 = 0x14`

### 3. Add r4 + r5 → r6

```text
PC=FFFF0008 IR=00C42800 RD=06 WB=0000001E
```

- Adds `r4 (0x0A)` + `r5 (0x14)`
- Result: `r6 = 0x1E`

### 4. Load Immediate → r7

```text
PC=FFFF000C IR=04E00100 RD=07 WB=00000100
```

- Loads `0x100` into `r7`
- Result: `r7 = 0x100`

### 5. Store r6 → Memory

```text
PC=FFFF0010 IR=34C70000 ST A=00000000 D=0000001E
```

- Stores the value of `r6` into memory address `0x00000000`
- Result: `MEM[0x00000000] = 0x1E`

### 6. Move / Load → r8

```text
PC=FFFF0014 IR=29070000 RD=08 WB=0000001E
```

- Moves or loads the value into `r8`
- Result: `r8 = 0x1E`

### 7. Halt

```text
HALT
```

- Execution terminates
- Triggers full register dump

### Final State Verification

Relevant registers:

- `r4 = 0x0A`
- `r5 = 0x14`
- `r6 = 0x1E`
- `r7 = 0x100`
- `r8 = 0x1E`

All other registers remain `0x00000000`, as expected.

### Conclusion

The execution trace confirms that:

- Instructions are decoded and executed correctly
- Arithmetic operations produce expected results
- Memory store operations write correct data
- Data movement between registers and memory is functional
- Final architectural state matches expected program behavior

This demonstrates correct end-to-end functionality of the RG Sonic32 CPU v1 on hardware using the debug and observability tooling.