# UART Interface

## Overview

This module implements a minimal UART transmit and receive interface for communication between the FPGA and a host system. It uses a standard **8N1 format** (1 start bit, 8 data bits, 1 stop bit) and a fixed baud rate derived from the system clock.

The design is intentionally simple: it operates as a **raw byte stream** with no buffering or protocol logic.

---

## Architecture

- `uart_tx` — serializes 8-bit data onto a single wire  
- `uart_rx` — reconstructs 8-bit data from a serial stream  

Both modules are fully synchronous and use a shared baud rate divider.

---

## Operation

- **Transmit:** On `tx_start`, sends start bit → 8 data bits (LSB first) → stop bit  
- **Receive:** Detects start bit, samples each bit at the center, reconstructs byte, asserts `rx_valid`  

Bit timing is controlled by:
```
CLKS_PER_BIT = system_clock / baud_rate
```
---

## Verification

Verified via loopback simulation (`tx → rx`), confirming correct transmission and reception of test bytes.

**Example Output:**
```
PASS: received 0xA5
PASS: received 0x3C
```
---

## Role in System

Provides a simple interface for:
- Debug output  
- Register inspection  
- Future program loading  