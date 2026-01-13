# 🧠 FPGA CPU Development

This repository documents the design and development of a custom CPU implemented on an Artix-7 FPGA using Verilog. The target platform is the **Alchitry Au V2** development board.

🎯 **Goal:** Build a fully custom CPU from the ground up, progressing from a structural hardware skeleton to a complete system capable of running real software workloads and, eventually, AI acceleration.

---

## 🧩 Target Platform

- **FPGA:** Xilinx Artix-7  
- **Board:** Alchitry Au V2  
- **HDL:** Verilog  
- **Toolchain:** Xilinx Vivado  

🔗 FPGA board information:  
https://shop.alchitry.com/products/alchitry-au

---

## 🗂️ Repository Structure and Versioning

The project is organized into **versioned design iterations**. Each folder labeled `v0`, `v1`, `v2`, etc. represents a major architectural milestone. Version numbers increase sequentially, with earlier versions serving as the foundation for later ones.

### 📌 Current Versions

- **v0** — Structural skeleton of the CPU

Each version folder contains:
- RTL source files for that version  
- A folder containing testbenches  
- One or more documents describing the goals, design decisions, limitations, and outputs of that version  

Files are intentionally **not organized using Vivado’s default `src/` and `sim/` layout**. Instead, each version is self-contained to improve clarity, traceability, and long-term maintainability.

---

## 🧠 Version Philosophy

This project deliberately separates **structural design**, **behavioral definition**, and **software capability** across versions. This avoids premature complexity and keeps architectural decisions clean and reviewable.

### 🧱 v0 — Structural Skeleton (Current)

- Core CPU modules exist in skeleton form  
- Interfaces and datapaths are defined  
- Clocking and reset strategy established  
- Modules are not yet fully integrated  
- No ISA, instruction semantics, or software execution  

Think of this version as **IKEA furniture before assembly** 🪑 — all parts exist, but nothing is optimized or fully connected yet.

---

## 🛣️ Roadmap

### 🧱 v0 — Structural Foundation
Skeleton CPU modules are constructed and interfaces are defined. The focus is on clean structure, correct timing, and forward compatibility. No instruction set or execution semantics exist at this stage.

### ⚙️ v1 — ISA and System Integration
The instruction set architecture and CPU specifications are defined. Modules from v0 are integrated into a functioning CPU. UART and basic video output are added. The CPU is capable of executing non-trivial software workloads, with **DOOM used as a late-stage validation target in simulation** 🎮.

### 🧩 v2 — Bare-Metal Software and Peripherals
The system is extended with a minimal bare-metal runtime and simple task management. Basic peripheral support is added (e.g., GPIO, timers, and selected external devices). The focus is on **hardware–software interaction**, not a full general-purpose operating system.

### 🤖 v3 — AI Acceleration
A neural network accelerator is integrated into the system, enabling the CPU to perform AI-related workloads and demonstrating heterogeneous compute capability.

---

## ✍️ Authorship

**Author:** Ryan Gaffere  

All work in this repository was designed and implemented solely by me.
