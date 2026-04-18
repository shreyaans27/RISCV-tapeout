# ML Inference SoC — Complete Documentation

## Revision: min_core_v4 (Final RTL)
## Process: TSMC 180nm
## Date: April 2026

---

## 1. Architecture Overview

### 1.1 Block Diagram

```
                    ┌──────────────────────────────────────────────────────────┐
                    │                      core_top                            │
                    │                                                          │
  pad_clk ─────────┤──► clk_div ──┬── clk_50 (50MHz) ─── SRAM/ROM negedge   │
  (100MHz)         │              └── clk_25 (25MHz) ──┬── core (gated)       │
                    │                                   ├── bus_xbar           │
  rst_n ───────────┤                                   ├── sram_ctrl (bus)    │
                    │                                   ├── rom_ctrl (bus)     │
  jtag_tck ────────┤──► jtag_bridge ◄──── toggle CDC ──┘── jtag_bridge (bus)  │
  jtag_tms ────────┤      │                                                    │
  jtag_tdi ────────┤      ├── core_rst_n ──► rv32im_core                      │
  jtag_tdo ◄───────┤      ├── core_clk_en ──► clock gate                     │
                    │      └── bus master ──► bus_xbar (master 1)              │
                    │                                                          │
                    │  rv32im_core ──► bus_xbar (master 0)                    │
                    │      ├── alu (split: fast + mul)                         │
                    │      ├── regfile (32x32)                                 │
                    │      └── dotprod4 (INT8 MAC)                            │
                    │                                                          │
                    │  bus_xbar ──┬── slave 0: sram_ctrl ──► SRAM macro pins  │
                    │             └── slave 1: rom_ctrl  ──► ROM macro pins   │
                    └──────────────────────────────────────────────────────────┘
```

### 1.2 Module Summary

| Module | Lines | Description | Clock Domain |
|--------|-------|-------------|-------------|
| `core_top` | ~120 | Top-level, clock gating, interconnect | — |
| `clk_div` | ~25 | 100→50→25 MHz divider (toggle FFs) | pad_clk |
| `rv32im_core` | ~450 | 3-stage RV32IM pipeline | clk_25 (gated) |
| `alu` | ~60 | Split ALU: `result_fast` + `mul_result_{ss,su,uu}` | combinational |
| `regfile` | ~25 | 32×32 register file, 2R+1W | clk_25 |
| `dotprod4` | ~50 | 4× INT8 multiply-accumulate | clk_25 |
| `bus_xbar` | ~150 | 2-master, 2-slave bus crossbar | clk_25 |
| `sram_ctrl` | ~100 | SRAM controller with macro timing | clk_25 + negedge + pad_clk |
| `rom_ctrl` | ~90 | ROM controller with macro timing | clk_25 + negedge + pad_clk |
| `jtag_bridge` | ~330 | IEEE 1149.1 TAP + bus master + core control | jtag_tck + clk_25 (CDC) |

**Total: 10 modules, 1800 lines, Verilator lint-clean**

### 1.3 Clock Domains

| Clock | Frequency | Period | Source | Used By |
|-------|-----------|--------|--------|---------|
| `pad_clk` | 100 MHz | 10 ns | External pad | clk_div, SRAM REN delay, ROM SAEN delay |
| `clk_50` | 50 MHz | 20 ns | clk_div stage 1 | SRAM/ROM negedge timing |
| `clk_25` | 25 MHz | 40 ns | clk_div stage 2 | Core, xbar, controllers (bus), JTAG bus master |
| `clk_core_gated` | 25 MHz (gated) | 40 ns | clk_25 & gate latch | rv32im_core only |
| `jtag_tck` | 1-10 MHz | variable | External pad | JTAG TAP state machine |

### 1.4 Memory Map

| Address Range | Size | Device | Access |
|---------------|------|--------|--------|
| `0x08000000 – 0x08001FFF` | 8 KB | SRAM | R/W (firmware + data + stack) |
| `0x20000000 – 0x20003FFF` | 16 KB | ROM | Read-only (weight storage) |

### 1.5 Top-Level Ports

```verilog
// Clock and Reset
input  pad_clk            // 100 MHz pad clock
input  rst_n              // Active-low system reset

// JTAG Interface
input  jtag_tck           // JTAG clock (1-10 MHz)
input  jtag_tms           // JTAG mode select
input  jtag_tdi           // JTAG data in
output jtag_tdo           // JTAG data out

// SRAM Macro Pins (directly to analog macro)
output sram_den           // Decoder enable (active high)
output sram_addr[7:0]     // Row address A<7:0>
output sram_col_addr[2:0] // Column mux C<2:0>
output sram_prechg        // Precharge (active low)
output sram_ren           // Read/sense enable
output sram_wen           // Write enable
output sram_en            // Column mux enable
output sram_din[31:0]     // Data in
input  sram_dout[31:0]    // Data out

// ROM Macro Pins (directly to analog macro)
output rom_wl_addr[7:0]   // Word line address ADDR<7:0>
output rom_col_in[3:0]    // Column mux input IN<3:0>
output rom_preen          // Precharge enable (active high = precharging)
output rom_wlen           // Word line enable
output rom_saen           // Sense amp enable
input  rom_dout[31:0]     // Data out

// Debug (directly to test pads)
output debug_pc[31:0]     // Current program counter
output debug_resp_valid   // Memory response valid
```

---

## 2. SRAM Controller Timing

### 2.1 Address Mapping

```
Bus byte address [31:0] → SRAM:
  addr[12:5] → row address A<7:0> (256 rows)
  addr[4:2]  → column mux C<2:0>  (8 columns)
  256 × 8 = 2048 words × 4 bytes = 8 KB
```

### 2.2 Read Cycle (40ns = 1 clk_25 period)

```
time:       0              20             30             40
clk_25:     ┌──────────────────────────────┐
            │            HIGH              │     LOW
            └──────────────────────────────┘
            ↑posedge                       ↑negedge              ↑posedge

pad_clk:    ┌────┐    ┌────┐    ┌────┐    ┌────┐    ┌────┐    ┌────┐
            │    │    │    │    │    │    │    │    │    │    │    │
            └────┘    └────┘    └────┘    └────┘    └────┘    └────┘
            0    5    10   15   20   25   30   35   40

posedge clk_25 (0ns):   ADDR, COL stable. WEN=0, REN=1 (from posedge FF)
                        PRECHG=LOW, DEN=LOW, EN=LOW (from negedge FF, prev cycle)

negedge clk_25 (20ns):  PRECHG=HIGH, DEN=HIGH, EN=HIGH (negedge FF fires)
                        Precharge had 20ns. Wordline and sense path now active.

negedge pad_clk (22.5ns): REN=HIGH (negedge pad_clk FF fires, 2.5ns after DEN)
                          Sense amplifier enabled.

next posedge clk_25 (40ns): DOUT valid (had 17.5ns to settle).
                            Controller latches DOUT, asserts resp_valid.
```

### 2.3 Write Cycle

Same timing as read, except WEN=1, REN=0. Data is driven into cells when DEN goes high at negedge clk_25.

### 2.4 Bus Handshake (3 clk_25 cycles)

```
Cycle 1 (IDLE→ACCESS):  req_valid && req_ready → latch addr/data, start SRAM timing
Cycle 2 (ACCESS→RESPOND): negedge fires DEN/PRECHG/EN, next posedge latches DOUT
Cycle 3 (RESPOND→IDLE):  resp_valid=1, then back to idle
```

### 2.5 Restrictions

The SRAM macro has no byte-level write enable. All stores must be full 32-bit word writes (`SW` only). The firmware must never use `SB` or `SH` instructions. Byte/halfword loads (`LB`, `LH`, `LBU`, `LHU`) are supported — the core extracts the relevant byte/halfword from the 32-bit read.

---

## 3. ROM Controller Timing

### 3.1 Address Mapping

```
Bus byte address [31:0] → ROM:
  addr[9:2]   → word line address ADDR<7:0> (256 word lines)
  addr[13:10] → column mux input IN<3:0>    (16 columns)
  256 × 16 = 4096 words × 4 bytes = 16 KB
```

### 3.2 Read Cycle (40ns = 1 clk_25 period)

```
posedge clk_25 (0ns):   ADDR, COL_IN stable.
                        PREEN=HIGH (precharging), WLEN=LOW, SAEN=LOW

negedge clk_25 (20ns):  PREEN=LOW (precharge done), WLEN=HIGH (word line active)
                        Precharge had 20ns.

posedge pad_clk (25ns): SAEN=HIGH (sense amp fires, 5ns after WLEN)

next posedge clk_25 (40ns): DOUT valid (had 15ns to settle after SAEN).
                            Controller latches DOUT, asserts resp_valid.
```

### 3.3 ROM Pattern (Behavioral Model)

The ROM contains a deterministic test pattern:

```
pattern = (wl_addr[1:0] + col_in[1:0]) % 4
  0 → 0x00000000
  1 → 0x55555555
  2 → 0xAAAAAAAA
  3 → 0xFFFFFFFF
```

---

## 4. JTAG Interface

### 4.1 TAP State Machine

Standard IEEE 1149.1 TAP running on `posedge jtag_tck`. 16-state FSM controlled by TMS.

### 4.2 Instruction Register (3-bit)

| IR Value | Instruction | DR Length | Description |
|----------|-------------|-----------|-------------|
| `000` | BYPASS | 1 bit | Standard bypass (required by spec) |
| `001` | IDCODE | 32 bits | Returns `0xDEAD0001` |
| `010` | DATA_REG | 68 bits | Custom data register for all operations |

After TAP reset (TLR), IR defaults to IDCODE.

### 4.3 DATA_REG Format (68 bits)

**Shift-in (command):**

| Bits | Field | Description |
|------|-------|-------------|
| `[67:66]` | cmd | `00`=read, `01`=write, `10`=control, `11`=NOP |
| `[65:34]` | addr | 32-bit bus address |
| `[33:2]` | wdata | 32-bit write data or control bits |
| `[1:0]` | unused | Reserved |

**Shift-out (status, captured at Capture-DR):**

| Bits | Field | Description |
|------|-------|-------------|
| `[67:66]` | status | `00`=idle, `01`=done, `10`=busy |
| `[65:34]` | rdata | 32-bit read data from last read |
| `[33:2]` | pc | Current `debug_pc` value |
| `[1:0]` | core_state | `00`=reset, `01`=halted, `10`=running |

### 4.4 Commands

**Read Memory (cmd=00):**

Shift in `{2'b00, addr[31:0], 32'h0, 2'b00}`. After Update-DR, the bus master issues a read to `addr` through the crossbar. Wait for completion, then shift again with NOP (`cmd=11`) to capture the result in `rdata`.

**Write Memory (cmd=01):**

Shift in `{2'b01, addr[31:0], data[31:0], 2'b00}`. After Update-DR, the bus master issues a write.

**Control (cmd=10):**

| wdata[3:0] | Command | Action |
|------------|---------|--------|
| `0001` | RESET | Hold core in reset, halt |
| `0010` | RELEASE | Release reset, free-run |
| `0100` | STEP | Release reset, execute one clk_25 cycle, re-halt |
| `1000` | HALT | Halt core (clock gated), keep out of reset |

**NOP (cmd=11):**

No bus transaction, no control action. Used to capture status without side effects.

### 4.5 CDC (Clock Domain Crossing)

The TAP (posedge jtag_tck) communicates with the bus master and core control (posedge clk_25) via a toggle synchronizer:

1. On Update-DR with IR=DATA, `update_toggle` flips in TCK domain
2. `cmd_reg`, `addr_reg`, `wdata_reg` are latched in TCK domain (stable)
3. In clk_25 domain: 3-FF synchronizer detects toggle edge → `trigger` pulse
4. On `trigger`, bus master reads `cmd_reg`/`addr_reg`/`wdata_reg` (safe because TCK << clk_25, so values are stable for many clk_25 cycles before trigger arrives)

**Constraint:** TCK must be slower than clk_25/2 = 12.5 MHz. Standard JTAG speeds (1-10 MHz) are safe.

### 4.6 Clock Gating

The core clock is gated by JTAG:

```verilog
always @(*) begin
    if (!clk_25)
        clk_gate_latch = core_clk_en;  // ICG latch
end
assign clk_core_gated = clk_25 & clk_gate_latch;
```

`core_clk_en = ~core_in_reset && (~core_halted || step_active)`

When `core_clk_en=0`, the core clock stops. The bus infrastructure (xbar, controllers) continues running on ungated `clk_25` so JTAG can still access memory while the core is halted.

---

## 5. Processor Pipeline

### 5.1 Pipeline Stages

```
S_FETCH   → issue read to SRAM at PC
S_FETCH_W → wait for SRAM response (instruction)
S_EXECUTE → decode + execute
S_MUL_W   → (MUL only) 2nd cycle for pipelined multiply
S_MEM     → issue load/store to SRAM/ROM
S_MEM_W   → wait for SRAM/ROM response (data)
```

### 5.2 Split ALU

The ALU has two separate outputs to break the multiplier critical path:

- `result_fast[31:0]` — add/sub/logic/shift/slt ONLY. No multiplier in combinational cone. Used for 1-cycle instructions.
- `mul_result_ss/su/uu[63:0]` — raw multiplier outputs. Feed ONLY into `mul_result_reg` pipeline register. Used for 2-cycle MUL instructions.

### 5.3 Instruction Support

All RV32IM instructions except `SB`, `SH` (SRAM only supports word writes):

- **ALU:** ADD, SUB, AND, OR, XOR, SLL, SRL, SRA, SLT, SLTU (+ immediate variants)
- **Multiply:** MUL, MULH, MULHSU, MULHU (2-cycle pipelined)
- **Memory:** LW, LH, LHU, LB, LBU, SW
- **Branch:** BEQ, BNE, BLT, BGE, BLTU, BGEU
- **Jump:** JAL, JALR
- **Upper:** LUI, AUIPC
- **Custom:** DotProd4 (opcode 0x0B, funct7: 0x00=DOTPROD, 0x01=ACC_RESET, 0x02=ACC_READ)

### 5.4 DotProd4 Custom Instruction

4× INT8 multiply-accumulate in one cycle:

```
DOTPROD4 rd, rs1, rs2:
  acc += rs1[7:0]*rs2[7:0] + rs1[15:8]*rs2[15:8] +
         rs1[23:16]*rs2[23:16] + rs1[31:24]*rs2[31:24]

ACC_RESET: acc = 0
ACC_READ rd: rd = acc
```

Encoded as custom-0 opcode (`0001011`).

---

## 6. Synthesis Constraints (SDC)

### 6.1 Clock Definitions

```tcl
# Primary clocks
create_clock -name pad_clk -period 10.0 [get_ports {pad_clk}]
create_clock -name jtag_clk -period 100.0 [get_ports {jtag_tck}]

# Generated clocks
create_generated_clock -name clk_50 \
    -source [get_ports {pad_clk}] \
    -divide_by 2 \
    [get_pins {u_clk_div/div2_reg/Q}]

create_generated_clock -name clk_25 \
    -source [get_pins {u_clk_div/div2_reg/Q}] \
    -divide_by 2 \
    [get_pins {u_clk_div/div4_reg/Q}]
```

### 6.2 Clock Groups

```tcl
# pad_clk, clk_50, clk_25 are synchronous (same source)
# jtag_clk is asynchronous to everything else
set_clock_groups -asynchronous \
    -group [get_clocks {pad_clk clk_50 clk_25}] \
    -group [get_clocks {jtag_clk}]
```

### 6.3 False Paths

```tcl
# SRAM macro pins — timing handled by controller posedge/negedge scheme
set_false_path -to [get_ports {sram_den sram_addr* sram_col_addr* \
    sram_prechg sram_ren sram_wen sram_en sram_din*}]
set_false_path -from [get_ports {sram_dout*}]

# ROM macro pins — same reasoning
set_false_path -to [get_ports {rom_wl_addr* rom_col_in* \
    rom_preen rom_wlen rom_saen}]
set_false_path -from [get_ports {rom_dout*}]

# Debug ports — not timing critical
set_false_path -to [get_ports {debug_pc* debug_resp_valid}]

# CDC paths (JTAG toggle synchronizer)
set_false_path -from [get_clocks {jtag_clk}] -to [get_clocks {clk_25}]
set_false_path -from [get_clocks {clk_25}] -to [get_clocks {jtag_clk}]
```

### 6.4 Multicycle Paths

```tcl
# Pipelined multiplier: mul_result_reg has 2 clk_25 cycles
set_multicycle_path 2 -setup -to [get_pins {u_core/mul_result_reg*/D}]
set_multicycle_path 1 -hold  -to [get_pins {u_core/mul_result_reg*/D}]
```

### 6.5 Rationale for False Paths

The SRAM and ROM macro pins are false-pathed because:

1. The controllers use posedge/negedge clk_25 to create the precharge/enable timing sequences
2. The actual timing to the macros is determined by clock edges, not combinational delay
3. The manual routing in Virtuoso from controller output FFs to macro pins must be kept short (<500µm, <1ns delay)
4. The timing margin is generous: 20ns per half-cycle for precharge/sense
5. The REN 2.5ns delay uses `negedge pad_clk` (a physical clock edge, not a combinational path)
6. The SAEN 5ns delay uses `posedge pad_clk` (same reasoning)

**These are NOT don't-care paths** — the timing is critical, it's just handled by the clock edge scheme rather than STA.

---

## 7. Place & Route Strategy

### 7.1 Approach

P&R only the digital logic (everything in `min_core_v4.v`). SRAM and ROM macros are external analog blocks — they are NOT in the synthesis netlist. Integration happens in Virtuoso.

### 7.2 Estimated Area

- Digital logic: ~8-12K gates at TSMC 180nm
- At 60% utilization: ~0.15-0.25 mm² core area
- Target die size: ≤ 400×400 µm for digital block
- Remaining 800×800 µm budget: SRAM + ROM macros

### 7.3 Negedge Flip-Flops

The SRAM and ROM controllers use negedge FFs for transition signals. Synthesis tools (Genus) will infer these as standard DFFs with inverted clock. In P&R (Innovus), the inverted clock tree will be handled automatically.

### 7.4 Export from Innovus

- GDS for Virtuoso import
- DEF for reference
- Post-route netlist for LVS

### 7.5 Virtuoso Integration

1. Import digital block GDS
2. Place SRAM and ROM analog macros adjacent to digital block
3. Manually route controller pins to macro pins (<500µm)
4. Route power (VDD/VSS) to all blocks
5. Connect pad_clk, rst_n, JTAG signals to pads
6. DRC/LVS on full chip

---

## 8. Verification Summary

### 8.1 Regression Tests (20 tests, 968 cycles)

| # | Test | Description |
|---|------|-------------|
| 1 | LUI | Load upper immediate |
| 2 | AUIPC | Add upper immediate to PC |
| 3 | ADDI | Add immediate |
| 4 | ANDI/ORI/XORI | Bitwise immediate ops |
| 5 | ADD/SUB | Register arithmetic |
| 6 | AND/OR/XOR | Register bitwise ops |
| 7 | SLT/SLTU/SLTI | Set-less-than variants |
| 8 | Shifts (imm) | SLLI/SRLI/SRAI |
| 9 | Shifts (reg) | SLL/SRL/SRA |
| 10 | SW/LW | Word store and load |
| 11 | LH/LHU | Halfword load (from known word) |
| 12 | LB/LBU | Byte load (from known word) |
| 13 | BEQ/BNE | Conditional branches |
| 14 | BLT/BGE | Signed comparison branches |
| 15 | JAL/JALR | Jump and link |
| 16 | MUL | 32×32 multiply (pipelined, 2 cycles) |
| 17-19 | ROM reads | 4 patterns verified via core |
| 20 | DOTPROD4 | INT8 MAC: basic, accumulate, signed |

### 8.2 JTAG Tests (8 tests)

| # | Test | Description | Verifies |
|---|------|-------------|----------|
| 1 | IDCODE | Read IDCODE register | TAP FSM, IR, IDCODE shift |
| 2 | BYPASS | 1-bit echo through bypass | BYPASS register |
| 3 | SRAM W/R | Write 17 words, read back all | Bus master write/read, CDC, SRAM ctrl |
| 4 | Core Run | Load firmware via JTAG, run, verify result | RELEASE cmd, core execution, result readout |
| 5 | Single-Step | Step core, verify PC advances | STEP cmd, clock gating, PC readback |
| 6 | Halt/Resume | Run core, HALT mid-execution, RELEASE, verify completion | HALT cmd, clock gating, resume |
| 7 | ROM Read | Read 5 ROM addresses, verify patterns | ROM controller via JTAG, address mapping |
| 8 | TAP Reset | Force TLR, verify IDCODE still works | TAP reset recovery |

---

## 9. Post-Tapeout Testing

### 9.1 Required Hardware

| Item | Specification | Approximate Cost |
|------|---------------|-----------------|
| FTDI FT2232H breakout board | Dual-channel USB-to-serial/JTAG | $15-25 |
| Custom PCB | Chip socket + JTAG header + power regulators | $50-100 (PCB fab) |
| USB cable | USB-A to Mini-B (for FTDI) | $5 |
| Power supply | 1.8V regulated (TSMC 180nm VDD) | $20 |
| Logic analyzer (optional) | Saleae Logic 8 or similar | $150+ |
| Oscilloscope (optional) | For clock/timing verification | Lab equipment |

### 9.2 PCB Design Requirements

**Power:**

- VDD = 1.8V (TSMC 180nm core voltage)
- VSS = GND
- Decoupling capacitors: 100nF ceramic close to each VDD pin, 10µF bulk on board
- Separate analog and digital ground planes if possible

**Clock:**

- 100 MHz oscillator module connected to `pad_clk`
- Use a TCXO (temperature-compensated crystal oscillator) for stability
- Keep clock trace short, impedance-matched if possible

**JTAG Header (2×5 pin, ARM standard):**

```
Pin 1: VDD (3.3V reference for FTDI, NOT chip VDD)
Pin 2: TMS
Pin 3: GND
Pin 4: TCK
Pin 5: GND
Pin 6: TDO
Pin 7: (key, no pin)
Pin 8: TDI
Pin 9: GND
Pin 10: RST_N
```

Note: The FTDI outputs 3.3V JTAG signals. If the chip I/O is 1.8V, you need level shifters (e.g., TXS0104E) between the FTDI and chip pads.

**Debug Header (optional):**

Bring out `debug_pc[31:0]` to test points or a header for logic analyzer probing during bringup.

### 9.3 FTDI FT2232H Configuration

The FT2232H has two channels. Channel A is used for JTAG:

```
FT2232H Pin → JTAG Signal
ADBUS0 (TCK) → jtag_tck
ADBUS1 (TDI) → jtag_tdi
ADBUS2 (TDO) → jtag_tdo
ADBUS3 (TMS) → jtag_tms
```

### 9.4 OpenOCD Configuration

Create `ml_soc.cfg`:

```tcl
# Adapter configuration
adapter driver ftdi
ftdi vid_pid 0x0403 0x6010
ftdi channel 0
ftdi layout_init 0x0008 0x000b
ftdi layout_signal nSRST -data 0x0020

# JTAG speed (start slow for bringup, increase later)
adapter speed 1000

# Transport
transport select jtag

# TAP definition
jtag newtap mlsoc tap -irlen 3 -expected-id 0xDEAD0001

# Initialize
init

# Verify connection
scan_chain
```

### 9.5 OpenOCD Custom Commands

Create `ml_soc_commands.tcl`:

```tcl
# ============================================================
# ML SoC JTAG Commands for OpenOCD
# ============================================================

proc mlsoc_select_data {} {
    irscan mlsoc.tap 0x2
}

proc mlsoc_select_idcode {} {
    irscan mlsoc.tap 0x1
}

# Read IDCODE
proc mlsoc_idcode {} {
    mlsoc_select_idcode
    set val [drscan mlsoc.tap 32 0]
    puts "IDCODE: 0x$val"
    return "0x$val"
}

# Write 32-bit word to memory
proc mlsoc_write {addr data} {
    mlsoc_select_data
    # cmd=01 (write), addr, data, unused=00
    set cmd [format "%017x" [expr {(1 << 66) | ($addr << 34) | ($data << 2)}]]
    drscan mlsoc.tap 68 0x$cmd
    after 1
}

# Read 32-bit word from memory
proc mlsoc_read {addr} {
    mlsoc_select_data
    # cmd=00 (read), addr
    set cmd [format "%017x" [expr {($addr << 34)}]]
    drscan mlsoc.tap 68 0x$cmd
    after 1
    # NOP to capture result
    set resp [drscan mlsoc.tap 68 [format "%017x" [expr {3 << 66}]]]
    # Extract rdata from bits [65:34]
    set rdata [expr {("0x$resp" >> 34) & 0xFFFFFFFF}]
    return [format "0x%08x" $rdata]
}

# Core control commands
proc mlsoc_reset {} {
    mlsoc_select_data
    set cmd [format "%017x" [expr {(2 << 66) | (1 << 2)}]]
    drscan mlsoc.tap 68 0x$cmd
    after 1
    puts "Core: RESET"
}

proc mlsoc_release {} {
    mlsoc_select_data
    set cmd [format "%017x" [expr {(2 << 66) | (2 << 2)}]]
    drscan mlsoc.tap 68 0x$cmd
    after 1
    puts "Core: RELEASED"
}

proc mlsoc_halt {} {
    mlsoc_select_data
    set cmd [format "%017x" [expr {(2 << 66) | (8 << 2)}]]
    drscan mlsoc.tap 68 0x$cmd
    after 1
    puts "Core: HALTED"
}

proc mlsoc_step {} {
    mlsoc_select_data
    set cmd [format "%017x" [expr {(2 << 66) | (4 << 2)}]]
    drscan mlsoc.tap 68 0x$cmd
    after 1
}

# Read core status
proc mlsoc_status {} {
    mlsoc_select_data
    set resp [drscan mlsoc.tap 68 [format "%017x" [expr {3 << 66}]]]
    set val [expr {"0x$resp"}]
    set status [expr {($val >> 66) & 3}]
    set rdata [expr {($val >> 34) & 0xFFFFFFFF}]
    set pc [expr {($val >> 2) & 0xFFFFFFFF}]
    set cstate [expr {$val & 3}]

    set status_str [lindex {idle done busy error} $status]
    set cstate_str [lindex {reset halted running stepping} $cstate]

    puts [format "Status: %s  PC: 0x%08x  State: %s  Last Read: 0x%08x" \
        $status_str $pc $cstate_str $rdata]
}

# Load firmware from hex file
proc mlsoc_load_firmware {filename base_addr} {
    mlsoc_reset
    set fp [open $filename r]
    set addr $base_addr
    set count 0
    while {[gets $fp line] >= 0} {
        set line [string trim $line]
        if {$line eq "" || [string index $line 0] eq "#"} continue
        mlsoc_write $addr "0x$line"
        set addr [expr {$addr + 4}]
        incr count
    end
    close $fp
    puts "Loaded $count words starting at [format 0x%08x $base_addr]"
}

# Run firmware and wait for completion
proc mlsoc_run_and_wait {done_addr {timeout_ms 5000}} {
    mlsoc_release
    set start [clock milliseconds]
    while {1} {
        set val [mlsoc_read $done_addr]
        if {$val eq "0xffffffff"} {
            puts "Firmware completed"
            return 1
        }
        if {[expr {[clock milliseconds] - $start}] > $timeout_ms} {
            puts "ERROR: Timeout after ${timeout_ms}ms"
            mlsoc_halt
            return 0
        }
        after 10
    }
}

# ROM characterization: read all addresses
proc mlsoc_rom_characterize {{num_wl 256} {num_col 16}} {
    mlsoc_reset
    puts "ROM Characterization: ${num_wl} WL × ${num_col} COL"
    set errors 0
    for {set col 0} {$col < $num_col} {incr col} {
        for {set wl 0} {$wl < $num_wl} {incr wl} {
            set addr [expr {0x20000000 | ($col << 10) | ($wl << 2)}]
            set val [mlsoc_read [format "0x%08x" $addr]]

            # Expected pattern
            set pat [expr {($wl + $col) & 3}]
            switch $pat {
                0 { set exp "0x00000000" }
                1 { set exp "0x55555555" }
                2 { set exp "0xaaaaaaaa" }
                3 { set exp "0xffffffff" }
            }
            if {$val ne $exp} {
                puts [format "  MISMATCH WL=%d COL=%d: got %s exp %s" $wl $col $val $exp]
                incr errors
            }
        }
    }
    if {$errors == 0} {
        puts "ROM PASS: All [expr {$num_wl * $num_col}] addresses correct"
    } else {
        puts "ROM FAIL: $errors errors"
    }
}
```

### 9.6 Python Script (Alternative to OpenOCD)

For more control, use `pyftdi` directly:

```python
#!/usr/bin/env python3
"""ML SoC JTAG interface using pyftdi"""

from pyftdi.jtag import JtagEngine
from pyftdi.bits import BitSequence
import time

class MLSoC:
    IDCODE_VAL = 0xDEAD0001

    IR_BYPASS = 0b000
    IR_IDCODE = 0b001
    IR_DATA   = 0b010

    CMD_READ    = 0b00
    CMD_WRITE   = 0b01
    CMD_CONTROL = 0b10
    CMD_NOP     = 0b11

    CTRL_RESET   = 0x1
    CTRL_RELEASE = 0x2
    CTRL_STEP    = 0x4
    CTRL_HALT    = 0x8

    def __init__(self, url='ftdi://ftdi:2232h/1', frequency=1e6):
        self.jtag = JtagEngine(frequency=frequency)
        self.jtag.configure(url)
        self.jtag.reset()

    def write_ir(self, val):
        self.jtag.write_ir(BitSequence(val, length=3))

    def shift_dr_68(self, data):
        """Shift 68-bit DR, return captured data"""
        bs = BitSequence(data, length=68)
        result = self.jtag.shift_register(bs)
        return int(result)

    def read_idcode(self):
        self.write_ir(self.IR_IDCODE)
        result = self.jtag.shift_register(BitSequence(0, length=32))
        return int(result)

    def _build_cmd(self, cmd, addr=0, data=0):
        return (cmd << 66) | (addr << 34) | (data << 2)

    def write_mem(self, addr, data):
        self.write_ir(self.IR_DATA)
        self.shift_dr_68(self._build_cmd(self.CMD_WRITE, addr, data))
        time.sleep(0.001)

    def read_mem(self, addr):
        self.write_ir(self.IR_DATA)
        self.shift_dr_68(self._build_cmd(self.CMD_READ, addr))
        time.sleep(0.001)
        resp = self.shift_dr_68(self._build_cmd(self.CMD_NOP))
        rdata = (resp >> 34) & 0xFFFFFFFF
        return rdata

    def control(self, ctrl):
        self.write_ir(self.IR_DATA)
        self.shift_dr_68(self._build_cmd(self.CMD_CONTROL, 0, ctrl))
        time.sleep(0.001)

    def reset_core(self):
        self.control(self.CTRL_RESET)

    def release_core(self):
        self.control(self.CTRL_RELEASE)

    def halt_core(self):
        self.control(self.CTRL_HALT)

    def step_core(self):
        self.control(self.CTRL_STEP)

    def read_status(self):
        self.write_ir(self.IR_DATA)
        resp = self.shift_dr_68(self._build_cmd(self.CMD_NOP))
        return {
            'status': (resp >> 66) & 3,
            'rdata': (resp >> 34) & 0xFFFFFFFF,
            'pc': (resp >> 2) & 0xFFFFFFFF,
            'core_state': resp & 3,
        }

    def load_firmware(self, hex_file, base_addr=0x08000000):
        self.reset_core()
        addr = base_addr
        count = 0
        with open(hex_file) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                word = int(line, 16)
                self.write_mem(addr, word)
                addr += 4
                count += 1
        print(f"Loaded {count} words at 0x{base_addr:08x}")
        return count

    def run_and_wait(self, done_addr=0x08000B28, timeout=5.0):
        self.release_core()
        start = time.time()
        while time.time() - start < timeout:
            val = self.read_mem(done_addr)
            if val == 0xFFFFFFFF:
                return True
            time.sleep(0.01)
        print("ERROR: Timeout")
        self.halt_core()
        return False


# ============================================================
# Post-tapeout test sequence
# ============================================================

if __name__ == '__main__':
    soc = MLSoC()

    # Step 1: Verify JTAG connection
    print("=== Step 1: IDCODE ===")
    idcode = soc.read_idcode()
    print(f"  IDCODE = 0x{idcode:08x}")
    assert idcode == 0xDEAD0001, f"IDCODE mismatch!"
    print("  PASS")

    # Step 2: SRAM write/read test
    print("\n=== Step 2: SRAM Test ===")
    soc.reset_core()
    test_data = [0xDEADBEEF, 0x12345678, 0xCAFEBABE, 0x55AA55AA]
    for i, d in enumerate(test_data):
        soc.write_mem(0x08000800 + i*4, d)
    ok = True
    for i, d in enumerate(test_data):
        rb = soc.read_mem(0x08000800 + i*4)
        if rb != d:
            print(f"  FAIL: addr 0x{0x08000800+i*4:08x} got 0x{rb:08x} exp 0x{d:08x}")
            ok = False
    if ok:
        print("  PASS: SRAM write/read verified")

    # Step 3: Load and run firmware
    print("\n=== Step 3: Firmware Execution ===")
    soc.load_firmware("firmware.hex")
    if soc.run_and_wait():
        result = soc.read_mem(0x08000B20)
        print(f"  RESULT = 0x{result:08x}")
        if result == 1:
            print("  PASS")
        else:
            print(f"  FAIL: expected 1")
    else:
        print("  FAIL: timeout")

    # Step 4: ROM characterization
    print("\n=== Step 4: ROM Characterization ===")
    soc.reset_core()
    errors = 0
    patterns = [0x00000000, 0x55555555, 0xAAAAAAAA, 0xFFFFFFFF]
    for col in range(16):
        for wl in range(256):
            addr = 0x20000000 | (col << 10) | (wl << 2)
            val = soc.read_mem(addr)
            exp = patterns[(wl + col) & 3]
            if val != exp:
                print(f"  MISMATCH WL={wl} COL={col}: 0x{val:08x} != 0x{exp:08x}")
                errors += 1
    if errors == 0:
        print(f"  PASS: All {256*16} ROM words correct")
    else:
        print(f"  FAIL: {errors} mismatches")

    # Step 5: Single-step test
    print("\n=== Step 5: Single-Step ===")
    soc.reset_core()
    # Write NOPs
    for i in range(4):
        soc.write_mem(0x08000000 + i*4, 0x00000013)  # NOP
    soc.write_mem(0x08000010, 0x0000006f)  # j self

    pcs = []
    for i in range(20):
        soc.step_core()
        time.sleep(0.001)
        st = soc.read_status()
        pcs.append(st['pc'])

    print(f"  PCs: {['0x{:08x}'.format(p) for p in pcs[:10]]}")
    if pcs[-1] > 0x08000000:
        print("  PASS: PC advancing")
    else:
        print("  FAIL: PC stuck")
```

### 9.7 Step-by-Step Bringup Procedure

**Phase 1: Power and Clock**

1. Apply 1.8V to VDD, verify current draw is reasonable (< 50mA idle)
2. Verify 100 MHz clock on pad_clk with oscilloscope
3. Verify rst_n is being driven (pulled high with pullup + RC delay for clean power-on reset)

**Phase 2: JTAG Connection**

1. Connect FTDI board to JTAG header
2. Install OpenOCD: `sudo apt install openocd`
3. Run: `openocd -f ml_soc.cfg`
4. In OpenOCD console: `scan_chain` — should show TAP with IDCODE `0xDEAD0001`
5. If no response: check TCK frequency (try 100 kHz), verify TMS/TDI/TDO connections

**Phase 3: SRAM Verification**

1. `mlsoc_reset`
2. Write test pattern: `mlsoc_write 0x08000000 0xDEADBEEF`
3. Read back: `mlsoc_read 0x08000000` — should return `0xdeadbeef`
4. Write/read several addresses across the SRAM range
5. If reads return 0: check SRAM macro power, verify manual routing

**Phase 4: Core Execution**

1. Load simple firmware (e.g., `li t0, 42; sw t0, 0(s0); j self`)
2. `mlsoc_release`
3. Wait briefly, then `mlsoc_halt`
4. Read the stored value — should be 42
5. If core doesn't execute: single-step and check PC advancement

**Phase 5: ROM Characterization**

1. `mlsoc_reset`
2. Read ROM at `0x20000000` — check against expected pattern
3. Run full characterization: `mlsoc_rom_characterize`
4. Record any bit errors for ROM team

**Phase 6: Full System Test**

1. Load MUL test firmware via JTAG
2. Release core, poll for completion
3. Read result — should be `0x00000001` (PASS)
4. Load DotProd4 test, verify accumulator results
5. Load matrix multiply firmware when ready

---

## 10. Firmware Development

### 10.1 Toolchain

```bash
# Install RISC-V GCC toolchain
# On Arch Linux:
sudo pacman -S riscv64-elf-gcc riscv64-elf-binutils riscv64-elf-newlib

# Compile
riscv64-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles \
    -T firmware/link.ld -o firmware.elf firmware.S

# Disassemble (verify)
riscv64-elf-objdump -d firmware.elf

# Convert to hex for loading
riscv64-elf-objcopy -O verilog firmware.elf firmware.vhex
python3 firmware/hex_to_memh.py firmware.vhex > firmware.hex
```

### 10.2 Linker Script (`firmware/link.ld`)

```ld
MEMORY {
    SRAM (rwx) : ORIGIN = 0x08000000, LENGTH = 8K
}

SECTIONS {
    .text : {
        *(.text*)
    } > SRAM

    .data : {
        *(.data*)
    } > SRAM

    .bss : {
        *(.bss*)
    } > SRAM
}
```

### 10.3 Firmware Template

```asm
.section .text
.globl _start

.equ SRAM_BASE,   0x08000000
.equ ROM_BASE,    0x20000000
.equ RESULT_ADDR, 0x08000B20
.equ DONE_ADDR,   0x08000B28

_start:
    # Setup pointers
    lui     sp, %hi(0x08001FF0)        # Stack at top of SRAM
    addi    sp, sp, %lo(0x08001FF0)
    lui     s0, %hi(RESULT_ADDR)
    addi    s0, s0, %lo(RESULT_ADDR)
    lui     s1, %hi(DONE_ADDR)
    addi    s1, s1, %lo(DONE_ADDR)

    # ---- Your code here ----

    # Signal completion
    li      t0, 1                       # PASS = 1
    sw      t0, 0(s0)                   # Write result
    li      t0, -1
    sw      t0, 0(s1)                   # Write done flag (0xFFFFFFFF)

done:
    j       done                        # Spin forever
```

### 10.4 Important Firmware Constraints

1. **No SB or SH instructions** — SRAM only supports full 32-bit word writes. Use `SW` for all stores.
2. **LB/LH/LBU/LHU work fine** — the core extracts bytes/halfwords from the 32-bit SRAM read.
3. **Stack must be word-aligned** — `sp` should always be a multiple of 4.
4. **ROM is read-only** — writing to ROM addresses will hang (no write path exists).
5. **Result convention** — write `1` to `RESULT_ADDR` for PASS, test number for FAIL, `0xFFFFFFFF` to `DONE_ADDR` to signal completion.
6. **DotProd4 custom instructions** — use `.word` directive to encode:
   ```asm
   # DOTPROD4 rd, rs1, rs2 (funct7=0x00)
   # ACC_RESET (funct7=0x01)
   # ACC_READ rd (funct7=0x02)
   .word 0x0000000B | (rd << 7) | (rs1 << 15) | (rs2 << 20) | (funct7 << 25)
   ```

### 10.5 Loading Firmware via JTAG

```bash
# Compile
riscv64-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles \
    -T firmware/link.ld -o firmware.elf firmware.S

# Generate hex
python3 firmware/hex_to_memh.py \
    <(riscv64-elf-objcopy -O verilog firmware.elf /dev/stdout) > firmware.hex

# Load via OpenOCD
openocd -f ml_soc.cfg -c "source ml_soc_commands.tcl; mlsoc_load_firmware firmware.hex 0x08000000; mlsoc_run_and_wait 0x08000B28; mlsoc_read 0x08000B20; shutdown"

# Or via Python
python3 ml_soc_test.py
```

---

## 11. Known Limitations

1. **No interrupts** — the core has no interrupt controller or trap handling
2. **No CSR support** — only `mcycle` is readable via `csrr` (used for cycle counting)
3. **No byte/halfword stores** — SRAM limitation, firmware must use `SW` only
4. **Single-step granularity** — STEP advances one `clk_25` cycle, not one instruction. Multiple steps needed per instruction (fetch + execute cycles).
5. **No hardware breakpoints** — single-step and halt are the only debug mechanisms
6. **Fixed memory map** — SRAM at `0x08000000`, ROM at `0x20000000`, hardcoded in `bus_xbar`
7. **JTAG clock constraint** — TCK must be < 12.5 MHz (half of clk_25)

---

## 12. File Manifest

| File | Description |
|------|-------------|
| `syn/min_core_v4.v` | Concatenated RTL for synthesis (1800 lines, 10 modules) |
| `rtl/alu.v` | Split ALU (fast + multiply) |
| `rtl/regfile.v` | 32×32 register file |
| `rtl/dotprod4.v` | INT8 MAC custom instruction |
| `rtl/bus_xbar.v` | 2-master, 2-slave crossbar |
| `rtl/clk_div.v` | Clock divider (100→50→25 MHz) |
| `rtl/sram_ctrl.v` | SRAM controller with macro timing |
| `rtl/rom_ctrl.v` | ROM controller with macro timing |
| `rtl/jtag_bridge.v` | JTAG TAP + bus master + core control |
| `rtl/rv32im_core.v` | RV32IM pipeline |
| `rtl/core_top.v` | Top-level integration |
| `sim/tb_top.v` | Regression testbench (20 tests) |
| `sim/tb_jtag.v` | JTAG testbench (8 tests) |
| `firmware/test_regress.S` | Regression test firmware |
| `firmware/link.ld` | Linker script |
| `firmware/hex_to_memh.py` | Hex conversion utility |
| `docs/synthesis_and_pnr_guide.md` | Synthesis/P&R guide |
