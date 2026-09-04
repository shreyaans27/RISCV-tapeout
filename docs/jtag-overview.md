# ML Inference SoC: JTAG Bridge Integration & Bring-Up Guide

This document details the architecture, hardware interfacing requirements, and software stack for the custom JTAG bridge implemented on the ML Inference SoC. Because this SoC utilizes a custom 68-bit data register rather than a standard RISC-V Debug Module (DTM), standard GDB debuggers will not work out-of-the-box. This guide provides the necessary specifications to build custom test hardware and software scripts for chip bring-up.

---

## 1. Architecture & Theory of Operation

The `jtag_bridge` module spans two clock domains (`jtag_tck` and `clk_25`) and provides three primary functions: an IEEE 1149.1 TAP state machine, a system bus master, and a core execution controller.

### 1.1 Instruction Register (IR)
The TAP utilizes a 3-bit Instruction Register. 

| IR Value | Instruction | Length | Description |
| :--- | :--- | :--- | :--- |
| `000` | `BYPASS` | 1 bit | Standard IEEE bypass. |
| `001` | `IDCODE` | 32 bits | Returns the hardcoded device ID: `0xDEAD0001`. Defaults to this state on reset (TLR). |
| `010` | `DATA_REG` | 68 bits | Custom interface for memory access and core control. |

### 1.2 The 68-Bit Data Register (`DATA_REG`)
All interactions with the SoC bus and core occur through this register. 

**Shift-In (Host to Target Command):**
*   `[67:66]` **Command:** `00` (Read), `01` (Write), `10` (Control), `11` (NOP)
*   `[65:34]` **Address:** 32-bit memory address for read/write.
*   `[33:2]` **Write Data:** 32-bit data to write (or control bits if Command=`10`).
*   `[1:0]` **Reserved:** Unused (set to `00`).

**Shift-Out (Target to Host Response - Captured at Update-DR):**
*   `[67:66]` **Bus Status:** `00` (Idle), `01` (Done), `10` (Busy)
*   `[65:34]` **Read Data:** 32-bit data returned from the last completed read.
*   `[33:2]` **Program Counter:** Current 32-bit PC (`debug_pc`).
*   `[1:0]` **Core State:** `00` (Reset), `01` (Halted), `10` (Running)

### 1.3 Core Control Commands
When issuing a Control command (`cmd = 10`), the lower 4 bits of the `Write Data` field determine the action:
*   `0001`: **RESET** - Hold core in reset, halt execution.
*   `0010`: **RELEASE** - Release reset, free-run execution.
*   `0100`: **STEP** - Release reset, execute exactly one `clk_25` cycle, re-halt.
*   `1000`: **HALT** - Halt core (clock gated), keep out of reset.

### 1.4 Clock Domain Crossing (CDC) Constraint
Commands shifted into the TAP (`jtag_tck` domain) are latched on the `Update-DR` state. A toggle synchronizer passes a trigger to the SoC bus master (`clk_25` domain). 
*   **Hardware Constraint:** To guarantee the address and data registers are stable before the `clk_25` domain samples them, **`jtag_tck` must not exceed 12.5 MHz** (half of the 25 MHz core clock).

---

## 2. Hardware Interfacing & PCB Design

The TSMC 180nm process operates at **1.8V**. Connecting standard 3.3V JTAG adapters directly to the SoC will cause pad degradation or immediate failure. A custom breakout PCB with level shifting is required.

### 2.1 Recommended BOM (Bill of Materials)

| Component Role | Recommended IC | Justification |
| :--- | :--- | :--- |
| **USB/JTAG Bridge** | FTDI FT2232H | Industry-standard MPSSE engine. Natively supported by OpenOCD and PyFtdi. Highly stable clock generation. |
| **Level Shifter** | TI SN74AVC4T245 | Directional dual-supply bus transceiver. Do **not** use auto-sensing shifters (e.g., TXS0104E) as they struggle with JTAG edge rates and capacitive loads. |
| **ESD Protection** | Nexperia PRTR5V0U2X | Place near the JTAG header to protect the 1.8V logic from static discharge during cable insertion. |
| **Connectors** | 2x5 1.27mm Header | Standard ARM Cortex Debug spacing. |

### 2.2 PCB Schematic Notes

**1. Level Shifter Configuration (3.3V FTDI ↔ 1.8V SoC):**
*   **VCCA:** 3.3V (FTDI side)
*   **VCCB:** 1.8V (Target side)
*   **Direction Pins (DIR):** Hardwire TDI, TMS, and TCK to translate A → B. Hardwire TDO to translate B → A.

**2. Target Signal Pulls (1.8V Domain):**
*   `jtag_tms`: 10kΩ pull-up to 1.8V
*   `jtag_tdi`: 10kΩ pull-up to 1.8V
*   `jtag_tck`: 10kΩ pull-down to GND
*   `rst_n`: 10kΩ pull-up to 1.8V + 100nF capacitor to GND (RC power-on reset)

**3. FT2232H Pin Mapping (Channel A):**
*   `ADBUS0` → TCK (Output)
*   `ADBUS1` → TDI (Output)
*   `ADBUS2` → TDO (Input)
*   `ADBUS3` → TMS (Output)

---

## 3. Software Stack

Because this is a custom 68-bit TAP implementation, interaction requires direct bit-banging of the DR and IR registers. 

### 3.1 OpenOCD Implementation
OpenOCD handles the low-level USB transaction batching for the FT2232H. 

**`ml_soc.cfg`** (Adapter & TAP definition)
```tcl
adapter driver ftdi
ftdi vid_pid 0x0403 0x6010
ftdi channel 0
ftdi layout_init 0x0008 0x000b

# Max clock 12.5MHz, starting at 1MHz for safety
adapter speed 1000
transport select jtag

# Define the custom TAP
jtag newtap mlsoc tap -irlen 3 -expected-id 0xDEAD0001
init