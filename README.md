# 🧠 FPGA CPU Development

This repository documents the design and development of a custom CPU architecture implemented on an Artix-7 FPGA using Verilog. The target platform is the Alchitry Au V2 development board.

🎯 **Goal:** Design, implement, and evolve a fully custom CPU from the ground up, progressing from hardware bring-up to a usable compute platform, followed by performance optimization and domain-specific acceleration.

---

## 🧩 Target Platform

- **FPGA:** Xilinx Artix-7  
- **Board:** Alchitry Au V2  
- **HDL:** Verilog  
- **Toolchain:** Xilinx Vivado  

🔗 FPGA board information:  
https://shop.alchitry.com/products/alchitry-au

---

## 📍 Current Status

> 🚧 **Current Stage: v1-mini (Hardware Bring-Up Complete)**

- Custom CPU successfully implemented and synthesized  
- Simulation verified with working testbenches  
- Successfully brought up on FPGA hardware  
- Implementation/resource reports generated  
- Timing report generation currently under investigation  

Next milestone: **v1 - UART-based program loading and output capture**

---

## 🗂️ Repository Structure and Versioning

The project is organized into versioned architectural milestones. Each version represents a meaningful step in system capability and complexity.

### 📌 Versions

- **v1-mini (current)** : Functional CPU + hardware bring-up  
- **v1** : Usable system with UART interface (program loading + output)  
- **v2** : Performance upgrade (pipelining + cache) with benchmarking  
- **v3** : Neural network accelerator integration  

- **v0** : Structural CPU skeleton (initial groundwork)

Each version folder contains:
- RTL source files  
- Testbenches  
- Supporting documentation (design decisions, results, limitations)

Versions are intentionally self-contained rather than using Vivado’s default `src/` and `sim/` layout. This improves traceability and allows each stage of the architecture to be independently understood.

---

## 🧠 Version Philosophy

This project is structured to separate concerns across stages:

- **Bring-up (v1-mini)** → Prove correctness on hardware  
- **Usability (v1)** → Enable program I/O and observability  
- **Performance (v2)** → Improve architectural efficiency  
- **Specialization (v3)** → Add domain-specific acceleration  

Each stage builds on the previous one without introducing unnecessary complexity too early.

---

## 🧱 v1-mini - Hardware Bring-Up Baseline (Current)

- Custom ISA defined and implemented  
- All core modules integrated  
- Simulation produces correct outputs  
- Successfully deployed and executed on FPGA hardware  
- No pipelining or cache  
- No external I/O interface yet (UART pending)

This stage validates that the CPU architecture is functionally correct and physically realizable.

---

## 🛣️ Roadmap

### ⚙️ v1 - System Interface (Next)

- UART RX/TX integration  
- Program loading from host PC  
- Output/data dump from FPGA to host  
- Repeatable execution workflow  
- Improved hardware debugging and observability  

**Goal**: Transform the CPU into a usable experimental platform

---

### 🚀 v2 - Performance Architecture

- Pipeline implementation  
- Cache subsystem  
- Performance benchmarking and analysis  

Includes a report comparing:
- v1 vs v2 performance  
- Execution efficiency improvements  
- Architectural tradeoffs  

**Goal**: Improve execution speed and system efficiency

---

### 🤖 v3 - Neural Network Acceleration

- Integration of a neural network accelerator  
- CPU ↔ accelerator interface design  
- Workload-specific optimization  

Includes a report analyzing:
- Performance gains from acceleration  
- Resource tradeoffs  
- System-level impact  

**Goal**: Demonstrate hardware-accelerated parallel computing

---

## ✍️ Authorship

**Author:** Ryan Gaffere  

All work in this repository was designed and implemented solely by me.
