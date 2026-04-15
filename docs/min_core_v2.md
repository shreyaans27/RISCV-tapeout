# Minimal ML Inference Core — Complete Documentation

**Date:** April 13, 2026
**Author:** team2chips2026
**Process:** TSMC 180nm
**Repository:** git@github.com:shreyaans27/RISCV-tapeout.git

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Architecture](#2-architecture)
3. [Memory Map](#3-memory-map)
4. [Core Microarchitecture](#4-core-microarchitecture)
5. [Bus Protocol](#5-bus-protocol)
6. [Module Descriptions](#6-module-descriptions)
7. [DotProd4 Custom Instruction](#7-dotprod4-custom-instruction)
8. [ROM Structure & Controller](#8-rom-structure--controller)
9. [SRAM Structure & Controller](#9-sram-structure--controller)
10. [JTAG Bridge](#10-jtag-bridge)
11. [Verification Results](#11-verification-results)
12. [Synthesis Flow](#12-synthesis-flow)
13. [SRAM Macro Integration Guide](#13-sram-macro-integration-guide)
14. [ROM Macro Integration Guide](#14-rom-macro-integration-guide)
15. [P&R Flow (Innovus)](#15-pr-flow-innovus)
16. [File Inventory](#16-file-inventory)
17. [Lessons Learned from Chipyard Attempt](#17-lessons-learned-from-chipyard-attempt)
18. [Command Reference](#18-command-reference)

---

## 1. Project Overview

### Goal

Tape out a minimal ML inference SoC on TSMC 180nm that can:

- Accept a 28×28 binarized MNIST digit image via JTAG
- Run a CNN inference entirely on-chip using a custom DotProd4 instruction
- Return the predicted digit (0–9) via JTAG

### Why a Custom Core (Not Chipyard)

The original approach used Chipyard's TinyRocketConfig. After synthesis and P&R attempts, it was found to be ~5.7 mm² — 9× larger than the 0.8×0.8 mm area budget. The overhead came from:

- TileLink bus hierarchy (SBUS/CBUS/PBUS/FBUS): ~1.4 mm²
- Debug module with async crossings: ~0.85 mm²
- PMP checkers (×2): ~0.15 mm²
- ITLB: ~0.07 mm²
- CSR file: ~0.41 mm²
- Boot ROM, UART, PLIC, CLINT: ~0.4 mm²

The minimal custom core eliminates all of this, targeting ~10-12K gates (~0.1-0.2 mm²).

### Design Philosophy

- Only implement instructions the firmware actually uses
- Simple valid/ready bus — no TileLink overhead
- Behavioral memory models for simulation, swap with macros for tapeout
- Verify against known firmware execution, not ISA compliance suite

---

## 2. Architecture

### Block Diagram

```
                    ┌──────────────┐
                    │  JTAG Bridge │
                    │  TCK TMS     │
                    │  TDI TDO     │
                    └──────┬───────┘
                           │ Bus Master 1
                           │ (writes SRAM, reads results)
                           │
    ┌──────────────────────┴──────────────────────┐
    │              Simple Bus Crossbar              │
    │         2 Masters → 2 Slaves                  │
    │                                               │
    │  Address Decode:                              │
    │    0x08000000-0x08001FFF → Slave 0 (SRAM)    │
    │    0x20000000-0x20003FFF → Slave 1 (ROM)     │
    ├──────────────┬──────────────┬────────────────┤
    │              │              │                  │
    │     Bus Master 0           │                  │
    │              │              │                  │
┌───┴──────────────┴───┐   ┌─────┴─────┐   ┌──────┴──────┐
│    RV32IM Core        │   │   SRAM    │   │    ROM      │
│                       │   │   8 KB    │   │   16 KB     │
│  ┌─────────────────┐ │   │ @0x08000000│   │ @0x20000000 │
│  │ 3-Stage Pipeline│ │   │           │   │             │
│  │ Fetch → Decode  │ │   │ Firmware  │   │ Weights     │
│  │ → Execute/WB    │ │   │ + Data    │   │ (det.       │
│  ├─────────────────┤ │   │ + Stack   │   │  pattern)   │
│  │ 32×32 RegFile   │ │   └───────────┘   └─────────────┘
│  ├─────────────────┤ │
│  │ ALU (RV32IM)    │ │
│  ├─────────────────┤ │
│  │ DotProd4 Unit   │ │
│  │ (4× INT8 MAC)   │ │
│  └─────────────────┘ │
└───────────────────────┘
```

### Port List (core_top)

| Port | Direction | Width | Description |
|------|-----------|-------|-------------|
| `clk` | input | 1 | System clock |
| `rst_n` | input | 1 | Active-low reset |
| `jtag_tck` | input | 1 | JTAG clock |
| `jtag_tms` | input | 1 | JTAG mode select |
| `jtag_tdi` | input | 1 | JTAG data in |
| `jtag_tdo` | output | 1 | JTAG data out |

### Estimated Gate Count

| Block | Estimated Gates |
|-------|----------------|
| RV32IM core (pipeline + control) | ~3,000 |
| Register file (32×32) | ~2,000 |
| ALU (add/sub/logic/shift/mul) | ~2,500 |
| DotProd4 (4× INT8 MAC) | ~2,500 |
| Bus crossbar (2×2) | ~500 |
| SRAM controller (behavioral) | ~200 |
| ROM controller (behavioral) | ~200 |
| JTAG bridge (stub/full) | ~500-2,000 |
| **Total** | **~11,000-13,000** |

---

## 3. Memory Map

### Address Space

| Address Range | Size | Device | Access |
|---------------|------|--------|--------|
| `0x08000000 – 0x08001FFF` | 8 KB | SRAM | Read/Write/Execute |
| `0x20000000 – 0x20003FFF` | 16 KB | ROM | Read-only |

### SRAM Internal Layout (for MNIST firmware)

| Offset | Address | Size | Contents |
|--------|---------|------|----------|
| `0x0000` | `0x08000000` | ~2 KB | Firmware code (.text) — reset vector |
| `0x0800` | `0x08000800` | 784 B | Image input (28×28 uint8, JTAG writes) |
| `0x0B20` | `0x08000B20` | 1 B | RESULT_ADDR — predicted digit 0-9 |
| `0x0B28` | `0x08000B28` | 1 B | DONE_ADDR — 0xFF when inference complete |
| `0x0A00` | `0x08000A00` | 256 B | Scratch area (for load/store tests) |
| `0x0C00` | `0x08000C00` | 1568 B | conv1_out buffer |
| `0x1210` | `0x08001210` | 784 B | fc_in buffer |
| `0x1510` | `0x08001510` | 256 B | fc1_out buffer |
| `0x1610` | `0x08001610` | 40 B | logits buffer |
| `0x1800` | `0x08001800` | ~2 KB | Stack (grows down from 0x08002000) |

### ROM Address Mapping

```
Byte address: 0x20000000 + offset

  offset[9:2]   → WL address (8 bits, 256 word lines)
  offset[13:10]  → column mux address (4 bits, 16 groups)
  offset[1:0]   → byte lane (for lb instruction)

Total: 256 WL × 16 col × 32 bits/read = 16 KB
```

### ROM Data Pattern

The ROM uses a deterministic pattern based on word line and column mux addresses:

```
pattern = (wl_addr[1:0] + col_mux_addr[1:0]) % 4

pattern 0 → all bytes 0x00 → word 0x00000000
pattern 1 → all bytes 0x55 → word 0x55555555
pattern 2 → all bytes 0xAA → word 0xAAAAAAAA
pattern 3 → all bytes 0xFF → word 0xFFFFFFFF
```

Example reads:

| Byte Address | WL (offset[9:2]) | COL (offset[13:10]) | Pattern | 32-bit Word |
|-------------|-------------------|---------------------|---------|-------------|
| 0x20000000 | 0 | 0 | 0 | 0x00000000 |
| 0x20000004 | 1 | 0 | 1 | 0x55555555 |
| 0x20000008 | 2 | 0 | 2 | 0xAAAAAAAA |
| 0x2000000C | 3 | 0 | 3 | 0xFFFFFFFF |
| 0x20000010 | 4 | 0 | 0 | 0x00000000 |
| 0x20000400 | 0 | 1 | 1 | 0x55555555 |

---

## 4. Core Microarchitecture

### Pipeline Stages

```
S_FETCH → S_FETCH_W → S_EXECUTE → [S_MEM → S_MEM_W] → back to S_FETCH
                                    ↑ only for loads/stores
```

**S_FETCH (1 cycle):** Assert `req_valid` with `req_addr = pc`, `req_wen = 0`. Move to S_FETCH_W.

**S_FETCH_W (1+ cycles):** Wait for `resp_valid`. Latch instruction into `instr` register. Move to S_EXECUTE.

**S_EXECUTE (1 cycle):** Decode and execute instruction. For most instructions (arithmetic, branches, jumps), writeback happens here and we go back to S_FETCH. For loads/stores, compute address and move to S_MEM.

**S_MEM (1 cycle):** Assert `req_valid` with computed address. For stores, set `req_wen = 1` with aligned data and byte mask. Move to S_MEM_W.

**S_MEM_W (1+ cycles):** Wait for `resp_valid`. For loads, latch and align response data, write to register file. Advance PC and go to S_FETCH.

### Reset Vector

`0x08000000` — first instruction fetched from SRAM base.

### Instruction Throughput

- Simple instructions (ALU, branch, jump): **4 cycles** (fetch + fetch_wait + execute + fetch)
- Load/Store: **6 cycles** (fetch + fetch_wait + execute + mem + mem_wait + fetch)
- All instructions stall on memory latency

### Supported Instructions

| Category | Instructions |
|----------|-------------|
| Upper Immediate | LUI, AUIPC |
| Jumps | JAL, JALR |
| Branches | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Loads | LB, LH, LW, LBU, LHU |
| Stores | SB, SH, SW |
| Arithmetic Imm | ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI |
| Arithmetic Reg | ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND |
| Multiply | MUL, MULH, MULHSU, MULHU |
| System | CSRRS (mcycle only), FENCE (NOP), ECALL/EBREAK (NOP) |
| Custom | DOTPROD4, ACC_RESET, ACC_READ (opcode 0x0B) |

### NOT Supported (not needed)

- DIV, DIVU, REM, REMU (no division in firmware)
- Atomic instructions (AMO)
- Compressed instructions (C extension)
- Floating point
- Virtual memory, PMP
- Interrupts, exceptions (ecall/ebreak are NOPs)

### Key Design Decision: Combinational ALU

The ALU inputs (`alu_op`, `alu_a`, `alu_b`) are driven combinationally from the current instruction, NOT registered. This allows the ALU result to be used in the same cycle as decode:

```verilog
// Combinational — result available immediately in S_EXECUTE
wire [3:0]  alu_op = decoded_alu_op;
wire [31:0] alu_a  = (opcode == OP_AUIPC) ? pc : rs1_data;
wire [31:0] alu_b  = (opcode == OP_ARITH || opcode == OP_BRANCH) ? rs2_data :
                     (opcode == OP_STORE) ? imm_s : imm_i;
```

**Bug history:** The original design used registered ALU inputs (`<=`), which caused `alu_result` to use stale values. This was the root cause of register file corruption and X-valued store addresses.

---

## 5. Bus Protocol

### Signal Interface

```verilog
// Master → Slave (request)
output        req_valid,    // request is valid
output [31:0] req_addr,     // byte address
output [31:0] req_wdata,    // write data (stores only)
output [3:0]  req_wmask,    // byte write mask
output        req_wen,      // 0 = read, 1 = write
input         req_ready,    // slave can accept request

// Slave → Master (response)
input         resp_valid,   // response is valid
input  [31:0] resp_rdata    // read data
```

### Protocol Rules

1. Master asserts `req_valid` with address/data
2. Master holds all signals stable until `req_ready` is seen
3. Slave asserts `resp_valid` with read data (next cycle or later)
4. Master latches `resp_rdata` when `resp_valid` is high
5. `resp_valid` is asserted for exactly one cycle per request
6. For writes: `resp_valid` acknowledges the write completed
7. For reads: `resp_valid` + `resp_rdata` contains the read data

### Timing Diagram (Read)

```
        ┌───┐   ┌───┐   ┌───┐   ┌───┐
clk     │   │   │   │   │   │   │   │
        ┘   └───┘   └───┘   └───┘   └───
req_valid ──────────────┐
                        └────────────────
req_addr  ──ADDR────────────────────────
resp_valid               ┌───┐
                         │   │
                         └───┘
resp_rdata               DATA
```

### Crossbar Arbitration

- **Priority:** Master 0 (core) has priority over Master 1 (JTAG)
- **Address decode:** `addr[31:16] == 0x0800` → SRAM, `addr[31:16] == 0x2000` → ROM
- **State machine per slave:** IDLE → M0_ACTIVE or M1_ACTIVE → IDLE (on resp_valid)
- **No pipelining:** One transaction at a time per slave

---

## 6. Module Descriptions

### core_top.v — Top Level

Instantiates and connects all submodules. No logic of its own. Ports: `clk`, `rst_n`, `jtag_tck`, `jtag_tms`, `jtag_tdi`, `jtag_tdo`.

### rv32im_core.v — CPU Pipeline

The main processor. 3-stage state machine (Fetch/Execute/Memory). Contains the pipeline control, PC register, instruction register, immediate decoders, branch comparison, load/store alignment, mcycle counter, and instruction dispatch.

Key internal signals:
- `pc` — program counter (32-bit, reset to 0x08000000)
- `instr` — latched instruction from fetch
- `state` — pipeline state (S_FETCH through S_MEM_W)
- `mem_addr_reg` — saved memory address for load/store alignment

### regfile.v — Register File

32 registers × 32 bits. x0 hardwired to 0. 2 read ports (combinational), 1 write port (clocked). Write-forwarding: if reading and writing the same register in the same cycle, the read returns the new value.

### alu.v — Arithmetic Logic Unit

Purely combinational. Supports: ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU, MUL, MULH, MULHSU, MULHU. The multiply is a 32×32→64 bit operation; Genus will synthesize this as a multiplier macro or gate-level logic.

### dotprod4.v — Custom MAC Unit

Single-cycle 4-way INT8 multiply-accumulate with internal 32-bit accumulator. Three operations selected by `funct7`:
- 0x00: DOTPROD4 — accumulate 4 INT8 products
- 0x01: ACC_RESET — clear accumulator to 0
- 0x02: ACC_READ — output accumulator value

### bus_xbar.v — Bus Crossbar

2 masters (core, JTAG) × 2 slaves (SRAM, ROM). Address decode on upper 16 bits. Per-slave arbitration state machine with core priority. Fully combinational data path, registered arbitration state.

### sram_ctrl.v — SRAM Controller (Behavioral)

8 KB (2048 × 32-bit words). Behavioral model using `reg [31:0] mem [0:2047]`. Supports byte-masked writes via `req_wmask`. Single-cycle response. Has `$readmemh` task for loading firmware in simulation.

**For tapeout:** Replace internal `reg` array with SRAM macro instance + state machine. See Section 13.

### rom_ctrl.v — ROM Controller (Behavioral)

16 KB ROM with deterministic pattern. Purely combinational data generation based on address decode. Single-cycle response. Read-only (ignores writes).

**For tapeout:** Replace combinational logic with ROM macro instance + read state machine. See Section 14.

### jtag_bridge.v — JTAG Bridge (Stub)

Currently a stub: passes `rst_n` through as `core_rst_n`, no bus activity, TDO tied low. For tapeout, implement full JTAG TAP with memory write capability. See Section 10.

---

## 7. DotProd4 Custom Instruction

### Encoding

R-type format in custom-0 opcode space:

```
 31      25 24    20 19    15 14  12 11     7 6      0
[ funct7  |  rs2  |  rs1  | 000  |   rd  | 0001011 ]
```

### Operations

| funct7 | Operation | Semantics | Assembly |
|--------|-----------|-----------|----------|
| 0x00 | DOTPROD4 | acc += Σ(sext8(rs1[i]) × sext8(rs2[i])) for i=0..3 | `.word 0x00B5050B` |
| 0x01 | ACC_RESET | acc = 0 | `.word 0x0200000B` |
| 0x02 | ACC_READ | rd = acc | `.word 0x0400060B` |

### Encoding Examples

```
ACC_RESET:  funct7=0000001, rs2=00000, rs1=00000, f3=000, rd=00000, op=0001011
            = 0000001_00000_00000_000_00000_0001011
            = 0x0200000B

DOTPROD4:   funct7=0000000, rs2=a1(01011), rs1=a0(01010), f3=000, rd=x0(00000), op=0001011
            = 0000000_01011_01010_000_00000_0001011
            = 0x00B5050B

ACC_READ:   funct7=0000010, rs2=00000, rs1=00000, f3=000, rd=a2(01100), op=0001011
            = 0000010_00000_00000_000_01100_0001011
            = 0x0400060B
```

### Internal Architecture

```
rs1[31:0] ──┬── sext8 ──┐
            ├── sext8 ──┤
            ├── sext8 ──┤   4× signed 8-bit multipliers
            └── sext8 ──┤        │
                        ├── × ───┤
rs2[31:0] ──┬── sext8 ──┤── × ───┤── adder tree ──► + acc ──► result
            ├── sext8 ──┤── × ───┤
            ├── sext8 ──┤── × ───┘
            └── sext8 ──┘
```

### Usage in FC Layer Firmware

```c
for (int i = 0; i < FC1_IN; i += 4) {
    uint32_t w = rom_lw(row_base + i);    // 4 weights from ROM
    uint32_t a;
    __builtin_memcpy(&a, &FC_IN[i], 4);  // 4 activations from SRAM
    DOTPROD4(acc, w, a);                  // 4 MACs in 1 instruction
}
```

---

## 8. ROM Structure & Controller

### Physical ROM Array

- **Cells:** 256 word lines × 256 bit lines × 2 bits per cell
- **Total capacity:** 256 × 256 × 2 = 131,072 bits = 16 KB
- **Read width:** 16 bit lines × 2 bits = 32 bits per read
- **Column mux:** 4-bit select, chooses every 16th bitline group
- **Pattern:** Repeating 00 01 10 11 across bit lines and word lines, shifted per WL

### Controller Interface (Current — Behavioral)

```verilog
module rom_ctrl (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        req_valid,
    output wire        req_ready,     // always 1 (behavioral)
    input  wire [31:0] req_addr,
    output reg         resp_valid,
    output reg  [31:0] resp_rdata
);
```

### Controller Interface (Tapeout — with ROM Macro)

```verilog
module rom_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // Bus interface (unchanged)
    input  wire        req_valid,
    output wire        req_ready,
    input  wire [31:0] req_addr,
    output reg         resp_valid,
    output reg  [31:0] resp_rdata,

    // ROM macro interface (NEW)
    output reg  [7:0]  rom_wl_addr,      // word line address
    output reg  [3:0]  rom_col_addr,     // column mux address
    output reg         rom_en,           // read enable
    input  wire [31:0] rom_data          // 32-bit read data
);
```

### Tapeout State Machine

```
IDLE → PRECHARGE → WL_ASSERT → SENSE → RESPOND → IDLE

IDLE:       Wait for req_valid. Latch address. Assert rom_en.
PRECHARGE:  ROM bitlines precharging (1 cycle)
WL_ASSERT:  Word line active, cells driving (1 cycle)
SENSE:      Sense amplifiers read data (1 cycle)
RESPOND:    Latch rom_data, assert resp_valid, return to IDLE
```

Exact timing depends on ROM macro specifications. For simulation, all states collapse to single-cycle.

---

## 9. SRAM Structure & Controller

### Physical SRAM

- **Size:** 8 KB = 2048 words × 32 bits
- **Type:** Single-port SRAM (read or write per cycle, not both)
- **Interface:** Standard SRAM macro pins (CK, CSN, WEN, A, D, Q, BWEN)

### Controller Interface (Current — Behavioral)

```verilog
module sram_ctrl (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        req_valid,
    output wire        req_ready,     // always 1 (behavioral)
    input  wire [31:0] req_addr,
    input  wire [31:0] req_wdata,
    input  wire [3:0]  req_wmask,
    input  wire        req_wen,
    output reg         resp_valid,
    output reg  [31:0] resp_rdata
);
```

### Controller Interface (Tapeout — with SRAM Macro)

```verilog
module sram_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // Bus interface (unchanged)
    input  wire        req_valid,
    output reg         req_ready,
    input  wire [31:0] req_addr,
    input  wire [31:0] req_wdata,
    input  wire [3:0]  req_wmask,
    input  wire        req_wen,
    output reg         resp_valid,
    output reg  [31:0] resp_rdata,

    // SRAM macro interface (NEW)
    output reg         sram_csn,        // chip select (active low)
    output reg         sram_wen,        // write enable (active low)
    output reg  [10:0] sram_addr,       // 11-bit word address (2048 words)
    output reg  [31:0] sram_wdata,      // write data
    output reg  [31:0] sram_bwen,       // bit write enable (active low)
    input  wire [31:0] sram_rdata       // read data
);
```

### Tapeout State Machine

```
IDLE → [READ_SETUP | WRITE_SETUP] → RESPOND → IDLE

IDLE:         Wait for req_valid. Decode read vs write.
READ_SETUP:   Assert CSN=0, WEN=1 (read), address on sram_addr.
              SRAM outputs data on sram_rdata after clock edge.
WRITE_SETUP:  Assert CSN=0, WEN=0 (write), address + data + bitmask.
              SRAM latches data on clock edge.
RESPOND:      Assert resp_valid with sram_rdata (for reads).
              For writes, resp_valid with no data.
```

### Byte Write Mask Translation

The bus uses 4-bit `req_wmask` (one bit per byte). SRAM macros typically use bit-level write enable (active low). Translation:

```verilog
// req_wmask[0] = byte 0 enable → sram_bwen[7:0] = 8'h00 (enable) or 8'hFF (disable)
sram_bwen[ 7: 0] = req_wmask[0] ? 8'h00 : 8'hFF;
sram_bwen[15: 8] = req_wmask[1] ? 8'h00 : 8'hFF;
sram_bwen[23:16] = req_wmask[2] ? 8'h00 : 8'hFF;
sram_bwen[31:24] = req_wmask[3] ? 8'h00 : 8'hFF;
```

---

## 10. JTAG Bridge

### Current State: Stub

The JTAG bridge is currently a stub that:
- Passes `rst_n` directly to `core_rst_n`
- Generates no bus traffic
- Ties `jtag_tdo` to 0
- In simulation, firmware is loaded via `$readmemh`

### Tapeout Implementation Plan

The full JTAG bridge needs:

1. **JTAG TAP controller** — standard state machine (Test-Logic-Reset → Run-Test-Idle → Shift-DR/IR → etc.)
2. **Instruction register** — select between IDCODE, BYPASS, and custom DATA_REG
3. **Data register** — shift in address (32 bits) + data (32 bits) + command (2 bits: read/write/reset)
4. **Bus master FSM** — converts shifted-in commands to bus transactions

### JTAG Protocol for Memory Access

```
Command encoding (2 bits):
  00 = NOP
  01 = WRITE (address + data → write to SRAM)
  10 = READ  (address → read from SRAM, shift out data)
  11 = RESET (assert/deassert core reset)

Shift sequence (66 bits):
  [65:64] = command
  [63:32] = address
  [31:0]  = write data (for WRITE) or don't care (for READ)
```

### Firmware Loading Sequence

```
1. JTAG sends RESET command (hold core in reset)
2. For each 32-bit word of firmware:
     JTAG shifts: cmd=WRITE, addr=0x08000000+offset, data=word
3. JTAG sends RESET command (release core from reset)
4. Core begins executing from 0x08000000
5. JTAG polls DONE_ADDR:
     JTAG shifts: cmd=READ, addr=0x08000B28
     Checks if result = 0xFF
6. JTAG reads RESULT_ADDR:
     JTAG shifts: cmd=READ, addr=0x08000B20
     Result is predicted digit 0-9
```

### Estimated Size

- JTAG TAP state machine: ~200 gates
- Shift registers (66 bits): ~200 gates
- Bus master FSM: ~100 gates
- **Total: ~500 gates**

Can also reuse the `DebugTransportModuleJTAG` from Chipyard (~768 gates) if you want a proven implementation — just extract it from the generated Verilog.

---

## 11. Verification Results

### Test Firmware: test_basic.S

Simple test: ROM read, DOTPROD4, store byte. **PASS in 108 cycles.**

### Test Firmware: test_regress.S (20 tests)

| Test | Category | What's Tested | Status |
|------|----------|--------------|--------|
| 1 | LUI | Load upper immediate | PASS |
| 2 | AUIPC | Add upper immediate to PC | PASS |
| 3 | ADDI | Add immediate (positive + negative) | PASS |
| 4 | ANDI/ORI/XORI | Logic immediates | PASS |
| 5 | ADD/SUB | Register arithmetic | PASS |
| 6 | AND/OR/XOR | Register logic | PASS |
| 7 | SLT/SLTU/SLTI | Set-less-than (signed + unsigned) | PASS |
| 8 | SLLI/SRLI/SRAI | Immediate shifts | PASS |
| 9 | SLL/SRL | Register shifts | PASS |
| 10 | SW/LW | Word store/load | PASS |
| 11 | SH/LH/LHU | Halfword store/load (signed + unsigned) | PASS |
| 12 | SB/LB/LBU | Byte store/load (signed + unsigned) | PASS |
| 13 | BEQ/BNE | Branch equal/not-equal | PASS |
| 14 | BLT/BGE | Branch less-than/greater-equal | PASS |
| 15 | JAL/JALR | Jump-and-link | PASS |
| 16 | MUL | Multiply (positive + negative) | PASS |
| 17 | ROM reads | All 4 patterns (0x00, 0x55, 0xAA, 0xFF) | PASS |
| 18 | DOTPROD4 | Basic: 1×4 + 1×3 + 1×2 + 1×1 = 10 | PASS |
| 19 | DOTPROD4 | Accumulate: 10 + 10 = 20 | PASS |
| 20 | DOTPROD4 | Signed: (-1)×1 × 4 = -4 | PASS |

**All 20 tests pass in 788 cycles.**

### Bugs Found and Fixed

| Bug | Symptom | Root Cause | Fix |
|-----|---------|------------|-----|
| X-valued store addresses | Store addr = 0xXXXXXXXX | ALU inputs were registered (`<=`), so `alu_result` used stale values | Changed ALU inputs to combinational wires |
| Register file corruption | Wrong values in registers after ADDI | Same ALU bug — `rf_wr_data <= alu_result` captured old ALU output | Same fix as above |
| Store byte lane wrong | SB wrote to wrong byte | `store_data`/`store_mask` used `alu_result[1:0]` (stale) instead of `mem_addr_reg[1:0]` | Changed to `mem_addr_reg[1:0]` |

---

## 12. Synthesis Flow

### Files for Synthesis

```
syn/minimal_core.v    — concatenated RTL (all 9 modules)
syn/minimal_core.sdc  — timing constraints
syn/genus_minimal.tcl — Genus synthesis script
```

### SDC Constraints

```
System clock: 100 MHz (10ns) — aggressive, to find max frequency
JTAG clock:   10 MHz (100ns)
Clock groups:  asynchronous
Max transition: 0.5ns
Max fanout: 10
```

### Genus Script (Legacy UI)

```tcl
set_db common_ui false
read_hdl -sv minimal_core.v
elaborate core_top
set_attribute auto_ungroup none /
set_attribute avoid true [find /libraries* -libcell msFlipFlop]
check_design -unresolved
read_sdc minimal_core.sdc
syn_generic -effort high
syn_map     -effort high
syn_opt     -effort high
report_timing / report_area / report_gates
write_hdl -mapped > minimal_core_synth.v
```

### Key Synthesis Notes

- `msFlipFlop` must be avoided (no LEF entry) — Genus uses `dfsbp_1` with SET_B tied high instead
- SRAM behavioral model synthesizes to flip-flops (~2048×32 = 65K FFs). This is expected for a first pass; blackbox for area-accurate synthesis
- The 32×32 multiplier in ALU will be the critical path

---

## 13. SRAM Macro Integration Guide

### When You Have the SRAM Macro

You need these files from the SRAM macro vendor/designer:

| File | Purpose |
|------|---------|
| `.lib` (all 3 PVT corners) | Timing characterization for synthesis |
| `.lef` | Physical dimensions and pin locations for P&R |
| `.gds` | Layout for final DRC/LVS |
| `.v` (behavioral) | Verilog model for simulation |

### Step 1: Identify SRAM Macro Pinout

Typical TSMC 180nm SRAM pins:

```verilog
module your_sram_8kb (
    input         CK,       // clock
    input         CSN,      // chip select (active low)
    input         WEN,      // write enable (active low)
    input  [10:0] A,        // 11-bit address (2048 words)
    input  [31:0] D,        // write data
    input  [31:0] BWEN,     // bit write enable (active low)
    output [31:0] Q         // read data
);
```

### Step 2: Update sram_ctrl.v

Replace the behavioral model with a state machine + macro instance:

```verilog
module sram_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // Bus interface (UNCHANGED)
    input  wire        req_valid,
    output reg         req_ready,
    input  wire [31:0] req_addr,
    input  wire [31:0] req_wdata,
    input  wire [3:0]  req_wmask,
    input  wire        req_wen,
    output reg         resp_valid,
    output reg  [31:0] resp_rdata
);

    wire [10:0] word_addr = req_addr[12:2];

    // SRAM macro signals
    reg         sram_csn;
    reg         sram_wen;
    reg  [10:0] sram_addr;
    reg  [31:0] sram_wdata;
    reg  [31:0] sram_bwen;
    wire [31:0] sram_rdata;

    // SRAM macro instance
    your_sram_8kb u_sram (
        .CK   (clk),
        .CSN  (sram_csn),
        .WEN  (sram_wen),
        .A    (sram_addr),
        .D    (sram_wdata),
        .BWEN (sram_bwen),
        .Q    (sram_rdata)
    );

    // State machine
    localparam IDLE    = 2'd0;
    localparam ACCESS  = 2'd1;
    localparam RESPOND = 2'd2;

    reg [1:0] state;
    reg       is_write;

    // Byte mask translation
    wire [31:0] bwen_expanded = {
        {8{~req_wmask[3]}},
        {8{~req_wmask[2]}},
        {8{~req_wmask[1]}},
        {8{~req_wmask[0]}}
    };

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            sram_csn   <= 1'b1;
            sram_wen   <= 1'b1;
            resp_valid <= 1'b0;
            req_ready  <= 1'b1;
            is_write   <= 1'b0;
        end else begin
            resp_valid <= 1'b0;

            case (state)
                IDLE: begin
                    if (req_valid) begin
                        sram_csn   <= 1'b0;          // select
                        sram_addr  <= word_addr;
                        sram_wen   <= ~req_wen;       // active low
                        sram_wdata <= req_wdata;
                        sram_bwen  <= req_wen ? bwen_expanded : 32'hFFFFFFFF;
                        is_write   <= req_wen;
                        req_ready  <= 1'b0;
                        state      <= ACCESS;
                    end
                end

                ACCESS: begin
                    sram_csn <= 1'b1;                 // deselect
                    state    <= RESPOND;
                end

                RESPOND: begin
                    resp_valid <= 1'b1;
                    resp_rdata <= is_write ? 32'h0 : sram_rdata;
                    req_ready  <= 1'b1;
                    state      <= IDLE;
                end
            endcase
        end
    end

endmodule
```

### Step 3: Update Synthesis Script

Add SRAM liberty to synthesis:

```tcl
set_attribute library [list \
    stdcells_4-07/gpdk_tt_1p8v_25c.lib \
    sram/your_sram_8kb_tt.lib \
]
```

Do NOT blackbox — the SRAM is now a real macro with timing.

### Step 4: Update Innovus

Add SRAM LEF:

```tcl
read_physical -lef lef/tech.lef
read_physical -lef lef/stdcells.lef
read_physical -lef sram/your_sram_8kb.lef   # NEW
```

Place SRAM macro manually on floorplan before standard cell placement.

---

## 14. ROM Macro Integration Guide

### ROM Physical Structure

- 256 word lines × 256 bit lines × 2 bits per cell
- Column mux: 4-bit select (16 groups)
- Read output: 32 bits per access
- Read-only — no write path

### Step 1: Identify ROM Macro Pinout

```verilog
module your_rom_16kb (
    input         CK,           // clock
    input         EN,           // read enable
    input  [7:0]  WL_ADDR,     // word line address (8 bits)
    input  [3:0]  COL_ADDR,    // column mux address (4 bits)
    output [31:0] DOUT          // 32-bit read data
);
```

### Step 2: Update rom_ctrl.v

```verilog
module rom_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    // Bus interface (UNCHANGED)
    input  wire        req_valid,
    output reg         req_ready,
    input  wire [31:0] req_addr,
    output reg         resp_valid,
    output reg  [31:0] resp_rdata
);

    wire [7:0] wl_addr  = req_addr[9:2];
    wire [3:0] col_addr = req_addr[13:10];

    // ROM macro signals
    reg         rom_en;
    reg  [7:0]  rom_wl;
    reg  [3:0]  rom_col;
    wire [31:0] rom_data;

    // ROM macro instance
    your_rom_16kb u_rom (
        .CK       (clk),
        .EN       (rom_en),
        .WL_ADDR  (rom_wl),
        .COL_ADDR (rom_col),
        .DOUT     (rom_data)
    );

    // State machine
    localparam IDLE    = 2'd0;
    localparam ACCESS  = 2'd1;
    localparam RESPOND = 2'd2;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            rom_en     <= 1'b0;
            resp_valid <= 1'b0;
            req_ready  <= 1'b1;
        end else begin
            resp_valid <= 1'b0;

            case (state)
                IDLE: begin
                    if (req_valid) begin
                        rom_en    <= 1'b1;
                        rom_wl    <= wl_addr;
                        rom_col   <= col_addr;
                        req_ready <= 1'b0;
                        state     <= ACCESS;
                    end
                end

                ACCESS: begin
                    rom_en <= 1'b0;
                    state  <= RESPOND;
                end

                RESPOND: begin
                    resp_valid <= 1'b1;
                    resp_rdata <= rom_data;
                    req_ready  <= 1'b1;
                    state      <= IDLE;
                end
            endcase
        end
    end

endmodule
```

### Step 3: Characterization

The ROM macro needs Liberty characterization for:
- Read access time (CK → DOUT)
- Setup/hold for address inputs
- Enable timing

---

## 15. P&R Flow (Innovus)

### Prerequisites

| Item | File | Status |
|------|------|--------|
| Synthesized netlist | `minimal_core_synth.v` | After synthesis |
| SDC | `minimal_core_synth.sdc` | After synthesis |
| Technology LEF | `tech.lef` | Have (from Chipyard flow) |
| Standard cell LEF | `stdcells.lef` | Have (sky130_fd_sc_hd_04-08.lef) |
| Standard cell Liberty | `gpdk_tt/ff/ss.lib` | Have (3 corners) |
| SRAM macro LEF | `sram.lef` | Need (when macro ready) |
| SRAM macro Liberty | `sram.lib` | Need (when macro ready) |
| ROM macro LEF | `rom.lef` | Need (when macro ready) |
| ROM macro Liberty | `rom.lib` | Need (when macro ready) |

### Innovus Step-by-Step Commands

```tcl
# ============================================================
# 1. Import Design
# ============================================================
read_physical -lef lef/tech.lef
read_physical -lef lef/stdcells.lef
# read_physical -lef sram/your_sram.lef    # when available
# read_physical -lef rom/your_rom.lef      # when available

read_netlist post_synth/minimal_core_synth.v -top core_top

read_libs [list \
    lib/gpdk_tt_1p8v_25c.lib \
    lib/gpdk_ff_1p95v_40c.lib \
    lib/gpdk_ss_1p60v_100c.lib]
# Also add SRAM/ROM libs when available

read_sdc post_synth/minimal_core_synth.sdc

# ============================================================
# 2. Power Connections
# ============================================================
globalNetConnect VDD -type pgpin -pin VDD -inst * -module {}
globalNetConnect VSS -type pgpin -pin VSS -inst * -module {}

# ============================================================
# 3. Floorplan (~0.8mm × 0.8mm target)
# ============================================================
floorPlan -coreMarginsBy die -site unithd -s 800 800 30 30 30 30

# If you have SRAM/ROM macros, place them first:
# placeInstance u_sram/u_sram_macro 100 100 R0
# placeInstance u_rom/u_rom_macro 100 500 R0
# addHaloToBlock 10 10 10 10 -allBlock

# ============================================================
# 4. Power Planning
# ============================================================
addRing -nets {VDD VSS} \
    -type core_rings -follow core \
    -layer {top METAL5 bottom METAL5 left METAL4 right METAL4} \
    -width {top 2.6 bottom 2.6 left 2.6 right 2.6} \
    -spacing {top 5 bottom 5 left 5 right 5} \
    -offset {top 0.2 bottom 0.2 left 0.2 right 0.2}

addStripe -nets {VDD VSS} \
    -layer METAL4 -direction vertical \
    -width 2.6 -spacing 26 \
    -set_to_set_distance 100 \
    -start_from left

sroute -connect {corePin floatingStripe} \
    -layerChangeRange {METAL2(2) METAL6(6)} \
    -nets {VDD VSS} \
    -allowJogging 1 \
    -allowLayerChange 1

# ============================================================
# 5. Physical Cells
# ============================================================
addEndCap -preCap decap_3 -postCap decap_3 -prefix ENDCAP
addWellTap -cell tap_1 -cellInterval 50 -prefix WELLTAP

# ============================================================
# 6. Placement
# ============================================================
setPlaceMode -congEffort auto -timingDriven 1 -clkGateAware 1
place_design

# ============================================================
# 7. Pre-CTS Timing
# ============================================================
timeDesign -preCTS -prefix preCTS -outDir timingReports
optDesign -preCTS

# ============================================================
# 8. Clock Tree Synthesis
# ============================================================
set_db cts_buffer_cells "buf_1 buf_2 buf_4 buf_8 buf_16"
ccopt_design

# ============================================================
# 9. Post-CTS Optimization
# ============================================================
optDesign -postCTS -setup
optDesign -postCTS -hold

# ============================================================
# 10. Routing
# ============================================================
setNanoRouteMode -quiet -drouteFixAntenna 1
setNanoRouteMode -quiet -routeTopRoutingLayer 5
setNanoRouteMode -quiet -routeBottomRoutingLayer 1
routeDesign -globalDetail

# ============================================================
# 11. Post-Route Optimization
# ============================================================
setAnalysisMode -analysisType OnChipVariation
timeDesign -postRoute -prefix postRoute -outDir timingReports
optDesign -postRoute
optDesign -postRoute -hold

# ============================================================
# 12. Reports & Export
# ============================================================
report_power > reports/power.rpt
report_area  > reports/area.rpt

saveNetlist outputs/minimal_core_pnr.v -phys
defOut -floorplan -routing outputs/minimal_core_pnr.def

# Save checkpoint
saveDesign minimal_core_final.enc
```

### Expected Results

With ~12K gates at TSMC 180nm:
- Die area: ~0.8 × 0.8 mm (0.64 mm²)
- Core utilization: ~50-60%
- Timing: should close at 50-100 MHz easily
- Power: <5 mW estimated

---

## 16. File Inventory

### Repository Structure

```
RISCV-tapeout/
├── rtl/
│   ├── core_top.v          — top-level SoC
│   ├── rv32im_core.v       — 3-stage CPU pipeline
│   ├── alu.v               — ALU (add/sub/logic/shift/mul)
│   ├── regfile.v           — 32×32 register file
│   ├── dotprod4.v          — 4× INT8 MAC unit
│   ├── bus_xbar.v          — 2×2 bus crossbar
│   ├── sram_ctrl.v         — 8KB SRAM controller (behavioral)
│   ├── rom_ctrl.v          — 16KB ROM controller (behavioral)
│   └── jtag_bridge.v       — JTAG bridge (stub)
├── sim/
│   ├── tb_top.v            — testbench
│   └── firmware.hex         — compiled test firmware
├── firmware/
│   ├── test_basic.S         — basic verification test
│   ├── test_regress.S       — 20-test regression suite
│   ├── link.ld             — linker script (SRAM at 0x08000000)
│   ├── hex_to_memh.py      — objcopy → $readmemh converter
│   ├── test_basic.elf       — compiled basic test
│   └── test_regress.elf     — compiled regression test
├── syn/
│   ├── minimal_core.v      — concatenated RTL for synthesis
│   ├── minimal_core.sdc    — timing constraints
│   └── genus_minimal.tcl   — Genus synthesis script
└── docs/
    └── .gitkeep
```

### Files on ese-chips

| File | Path | Purpose |
|------|------|---------|
| Concatenated RTL | `synthesis/minimal_core/minimal_core.v` | Synthesis input |
| SDC | `synthesis/minimal_core/minimal_core.sdc` | Timing constraints |
| Genus script | `synthesis/minimal_core/genus_minimal.tcl` | Synthesis automation |
| Stdcell Liberty | `stdcells/stdcells_4-07/gpdk_*.lib` | 3 PVT corners |
| Stdcell LEF | `innovus_pnr/lef/sky130_fd_sc_hd_04-08.lef` | Cell layouts |
| Tech LEF | `innovus_pnr/lef/tech_04-08.lef` | Layer definitions |

---

## 17. Lessons Learned from Chipyard Attempt

### What Was Tried

1. **MLInferenceConfig** (Gemmini + HugeCore) — way too large
2. **MnistSoCConfig** (SmallCore + scratchpad) — DCache Acquire issue
3. **MnistSoCConfig** (TinyCore + DTIM) — worked but 5.7mm²
4. **Minimal custom core** — current approach, fits in 0.64mm²

### Key Chipyard Errors and Fixes

| Error | Root Cause | Fix |
|-------|-----------|-----|
| `key not found: Location(mbus)` | AbstractConfig's MBUS scratchpad + WithIncoherentBusTopology | `WithNoScratchpads` |
| `No managers support Acquires` | WithNSmallCores DCache issues Acquire | Switch to `With1TinyCore` |
| 42 TLMonitor modules | Simulation-only assertion checkers | `WithoutTLMonitors` |
| msFlipFlop no LEF | Genus uses msFlipFlop but no layout exists | `set_attribute avoid true` |
| 438K gates | SRAM synthesized to flip-flops | Blackbox _ext modules |
| -37ns WNS in P&R | Design too large for cell library drive strength | **Abandoned — too big** |

### Why Custom Core Wins

| Metric | Chipyard TinyCore | Custom Core |
|--------|------------------|-------------|
| RTL lines | 30,931 | ~800 |
| Modules | 195 | 9 |
| Gate count (est.) | 60K (no SRAM) | ~12K |
| Area (est.) | 5.7 mm² | 0.2 mm² |
| Complexity | High (TileLink, diplomacy) | Low (simple bus) |
| Debug difficulty | Hard (deep hierarchy) | Easy (flat) |

---

## 18. Command Reference

### Local Machine (Arch Linux)

```bash
# Compile firmware
riscv64-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles \
    -T firmware/link.ld -o firmware/test.elf firmware/test.S

# Disassemble
riscv64-elf-objdump -d firmware/test.elf

# Convert to hex for simulation
python3 firmware/hex_to_memh.py \
    <(riscv64-elf-objcopy -O verilog firmware/test.elf /dev/stdout) \
    > sim/firmware.hex

# Lint check
verilator --lint-only syn/minimal_core.v

# Simulate with iverilog
iverilog -o sim/tb_top.vvp -I rtl sim/tb_top.v \
    rtl/core_top.v rtl/rv32im_core.v rtl/alu.v rtl/regfile.v \
    rtl/dotprod4.v rtl/bus_xbar.v rtl/sram_ctrl.v rtl/rom_ctrl.v \
    rtl/jtag_bridge.v
cd sim && vvp tb_top.vvp

# View waveforms
gtkwave sim/tb_top.vcd

# Concatenate for synthesis
for f in rtl/alu.v rtl/regfile.v rtl/dotprod4.v rtl/bus_xbar.v \
         rtl/sram_ctrl.v rtl/rom_ctrl.v rtl/jtag_bridge.v \
         rtl/rv32im_core.v rtl/core_top.v; do
    cat "$f"; echo ""
done > syn/minimal_core.v
```

### ese-chips (Synthesis & P&R)

```bash
# Copy RTL to ese-chips
scp syn/minimal_core.v syn/minimal_core.sdc syn/genus_minimal.tcl \
    team2chips2026@ese-chips.seas.upenn.edu:/home/home3/team2chips2026/synthesis/minimal_core/

# Run Genus
cd /home/home3/team2chips2026/synthesis/minimal_core
source /home/home3/team2chips2026/setup_cadence.sh
genus -legacy_ui -no_gui -files genus_minimal.tcl 2>&1 | tee genus_minimal.log

# Check results
cat outputs/gates.rpt
cat outputs/timing.rpt | head -30

# Launch Innovus
cd /home/home3/team2chips2026/innovus_pnr
source launch_innovus.sh
```

### acghaswell16 (Chipyard — if needed)

```bash
ssh shrey27@acghaswell16.seas.upenn.edu
cd ~/chipyard
conda activate /home/shrey27/chipyard/.conda-env
source env.sh
cd sims/verilator
make CONFIG=MnistSoCConfig verilog
```