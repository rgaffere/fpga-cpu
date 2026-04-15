# FPGA CPU — RG Sonic32

[![FPGA](https://img.shields.io/badge/Platform-Artix7-blue)]()
[![HDL](https://img.shields.io/badge/HDL-Verilog-orange)]()
[![Status](https://img.shields.io/badge/Status-v1--mini_complete-green)]()

This repository contains a fully custom 32-bit CPU implemented in Verilog and deployed on a Xilinx Artix-7 FPGA (Alchitry Au V2).

The project is developed in stages, progressing from a functional baseline CPU to a pipelined architecture with advanced features and performance analysis.

---

## 🚀 Project Overview

- 🧠 **Custom ISA** - Designed from scratch  
- ⚙️ **Full RTL Implementation** - Datapath, control unit, memory subsystem  
- 🔬 **Cycle-Accurate Simulation** - Verified execution and instruction flow  
- 🔌 **Hardware Bring-Up Complete** - Running on FPGA  
- 📊 **Performance Characterization** - CPI, latency, and throughput analysis  

---

## 📄 Documentation

### v1-mini (Baseline CPU)

- [Simulation, Validation & Performance Report](v1/docs/v1-mini%20Simulation%20%26%20Performance%20Report.pdf)  
  -> Functional correctness, execution trace, CPI, and performance metrics  

- [Post-Implementation Report](v1/docs/v1-mini%20Post-Implemlentation%20Report.pdf)  
  -> Timing, utilization, and hardware implementation results  

- [ISA Specification](v1/docs/v1%20Instruction%20Set%20Architecture%20(ISA)%20Specification.pdf)  
  -> Custom instruction set definition and encoding  

---

## 🧱 Architecture

The v1-mini CPU is a multi-cycle processor built as a finite state machine:

- FETCH -> EXECUTE -> MEMORY -> WRITEBACK -> BRANCH  
- Shared datapath resources across cycles  
- Deterministic instruction execution timing  

### Key Characteristics

- Non-pipelined design  
- Multi-cycle execution model  
- Instruction-dependent latency  
- Explicit control flow handling  

---

## 📊 Performance (v1-mini)

From RTL simulation:

- **Total Cycles:** 57  
- **Instructions Executed:** 9  
- **Average CPI:** ~6.3  
- **Estimated Throughput:** 12.7 MIPS (based on ~80 MHz estimate)

### Instruction Latency

| Instruction | Cycles |
|------------|--------|
| ADD / ADDI | 6 |
| SUB        | 6 |
| SW         | 8 |
| LW         | 9 |
| BEQ        | 5 |
| HALT       | 1 |

---

## 🧪 Validation

The CPU has been:

- ✅ Verified in cycle-accurate simulation
- ✅ Confirmed to execute correctly on real FPGA hardware
- ✅ Validated through register-level correctness checks
- ✅ Tested for branch behavior and control flow

---

## 🗺️ Roadmap

### v1 (in progress)
- UART debug module (register dump + I/O)
- Full hardware observability

### v2 (planned)
- 5-stage pipeline  
- Reduced CPI (~1–2 target)  
- Performance benchmarking vs v1  

### v3 (planned)
- Neural network accelerator  
- Hardware compute extensions  

---

## ✍️ Author

Ryan Gaffere  
