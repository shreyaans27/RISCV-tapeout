# min_core_v7 PnR — Handoff & Flow Reference

## 1. Current State (as of handoff)

### Where you are in the flow
Clock tree synthesis + post-CTS setup optimization **DONE**. Setup timing clean.
Next step: hold timing check + hold fixing.

### Completed steps
| Step | Status | Checkpoint | Time |
|---|---|---|---|
| LEF patching (antenna fix) | Done | `lef_v7/team2stdcells_final_wSideArea_patched_qrc.lef` | — |
| Innovus probe (0 antenna warnings) | Done | — | — |
| init_design | Done | — | — |
| Floorplan + pins + power | Done | `checkpoint_after_power_v7.enc` | — |
| place_design | Done | — | 4:47 |
| timeDesign -preCTS | Done | — | 0:10 |
| optDesign -preCTS | Done | `checkpoint_after_placeopt_v7.enc` | 8:00 |
| clock_opt_design (CTS + post-CTS opt) | Done | — | 3:10 |
| **timeDesign -postCTS** | **Next** | — | — |
| timeDesign -postCTS -hold | Todo | — | — |
| optDesign -postCTS -hold (pass 1) | Todo | — | — |
| optDesign -postCTS -hold (pass 2) | Todo | `checkpoint_after_cts_hold_v7.enc` | — |
| routeDesign | Todo | `checkpoint_after_route_v7.enc` | — |
| Post-route timing + opt | Todo | — | — |
| Export DEF/GDS | Todo | `checkpoint_final_v7.enc` | — |
| Calibre DRC / antenna | Todo | — | — |

### Key timing milestones so far
| Stage | WNS setup | TNS | DRVs |
|---|---|---|---|
| After place | +2.479 ns | 0 | 388 max_cap + 331 max_tran |
| After optDesign -preCTS | +2.915 ns | 0 | 0 |
| After clock_opt_design | +2.383 ns | 0 | 0 |

### CTS warnings (all harmless)
- IMPCCOPT-1023: skew target miss by 32 ps (target 250 ps, achieved 282 ps)
- IMPCCOPT-1033: one clock buffer over max_cap by 1 fF
- IMPCCOPT-1182 x4: clock_gating_cells property has no users
- IMPEXT-3530 x6: process node not set (Innovus infers from tech LEF)
- IMPSP-9025 x1: no scan chain

### Working directory
`/home/home3/team2chips2026/innovus_pnr/min_core_v5/`

### Innovus session
Currently sitting at `innovus>` prompt after clock_opt_design completed. The design is in memory. Do NOT exit or restore a checkpoint. Just continue with next commands.

### Files you need (all on server, do not touch)
- LEFs: `lef_v7/tech_v2_qrc.lef` + `lef_v7/team2stdcells_final_wSideArea_patched_qrc.lef`
- MMMC: `mmmc.tcl` (unchanged from v5, uses QRC tech file)
- Netlist: `core_top_mapped.v`
- SDC: `core_top_pnr.sdc` (loaded via mmmc.tcl)
- Checkpoints: `checkpoint_after_power_v7.enc.dat/`, `checkpoint_after_placeopt_v7.enc.dat/`

---

## 2. Full Flow Reference (setup → GDS)

Save this whole section as a reference. Every command is meant to be pasted at the
`innovus>` prompt unless noted otherwise. **All v7 checkpoints use `_v7` suffix**
to avoid overwriting v5.

### Step 0: Launch Innovus

```bash
cd /home/home3/team2chips2026/innovus_pnr/min_core_v5/
source /home/home3/team2chips2026/innovus_pnr/launch_innovus.sh
```

### Step 1: Setup + init_design

```tcl
set_global _enable_mmmc_by_default_flow $CTE::mmmc_default
suppressMessage ENCEXT-2799

# Raise warning limits so nothing gets truncated
setMessageLimit 10000 -id IMPLF-200
setMessageLimit 10000 -id IMPLF-201

# Point at lef_v7 (with antenna patch)
set init_lef_file {lef_v7/tech_v2_qrc.lef lef_v7/team2stdcells_final_wSideArea_patched_qrc.lef}
set init_mmmc_file mmmc.tcl
set init_verilog core_top_mapped.v
set init_top_cell core_top
set init_pwr_net VDD
set init_gnd_net VSS

init_design
```

Verify clean with IMPLF-200/201 = 0 and no **ERROR before proceeding.

### Step 2: Floorplan + Power

```tcl
# Global net connectivity
globalNetConnect VDD -type pgpin -pin VDD -inst *
globalNetConnect VSS -type pgpin -pin VSS -inst *

# Floorplan — 1000x1100 die, 25 um margins (will snap to grid automatically)
floorPlan -coreMarginsBy die -site core -d 1000 1100 25 25 25 25
```

### Step 3: Pin Placement

```tcl
setPinAssignMode -pinEditInBatch true

# North side — ROM pins (47 signals), METAL_2
editPin -side N -layer METAL_2 -pin {rom_dout[31] rom_dout[30] rom_dout[29] rom_dout[28] rom_dout[27] rom_dout[26] rom_dout[25] rom_dout[24] rom_dout[23] rom_dout[22] rom_dout[21] rom_dout[20] rom_dout[19] rom_dout[18] rom_dout[17] rom_dout[16] rom_dout[15] rom_dout[14] rom_dout[13] rom_dout[12] rom_dout[11] rom_dout[10] rom_dout[9] rom_dout[8] rom_dout[7] rom_dout[6] rom_dout[5] rom_dout[4] rom_dout[3] rom_dout[2] rom_dout[1] rom_dout[0] rom_wl_addr[0] rom_wl_addr[1] rom_wl_addr[2] rom_wl_addr[3] rom_wl_addr[4] rom_wl_addr[5] rom_wl_addr[6] rom_wl_addr[7] rom_col_in[0] rom_col_in[1] rom_col_in[2] rom_col_in[3] rom_wlen rom_preen rom_saen} -fixedPin 1 -spreadType CENTER -pinWidth 0.5 -pinDepth 1.5 -spacing 0.5 -unit MICRON

# West side — debug pins (34 signals), METAL_3 (now sized to match SRAM pins for DRC safety)
editPin -side W -layer METAL_3 -pin {debug_pc[0] debug_pc[1] debug_pc[2] debug_pc[3] debug_pc[4] debug_pc[5] debug_pc[6] debug_pc[7] debug_pc[8] debug_pc[9] debug_pc[10] debug_pc[11] debug_pc[12] debug_pc[13] debug_pc[14] debug_pc[15] debug_pc[16] debug_pc[17] debug_pc[18] debug_pc[19] debug_pc[20] debug_pc[21] debug_pc[22] debug_pc[23] debug_pc[24] debug_pc[25] debug_pc[26] debug_pc[27] debug_pc[28] debug_pc[29] debug_pc[30] debug_pc[31] debug_resp_valid} -fixedPin 1 -spreadType CENTER -pinWidth 0.5 -pinDepth 1.5 -spacing 0.5 -unit MICRON

# South side — JTAG + clock + reset (6 signals), METAL_3, larger pins
editPin -side S -layer METAL_3 -pin {pad_clk rst_n jtag_tck jtag_tms jtag_tdi jtag_tdo} -fixedPin 1 -spreadType CENTER -pinWidth 1.0 -pinDepth 1.5 -spacing 0.5 -unit MICRON

# East edge (edge 2) — SRAM pins, 80 signals total, matches physical SRAM pin order
# Order: A0..7, EN, DEN, PRECHG, WRITE_EN, READ_EN, C0..2,
#        interleaved IN15/OUT31 ... IN0/OUT16 ... IN31/OUT15 ... IN16/OUT0
editPin -edge 2 -layer METAL_3 -pin {sram_addr[0] sram_addr[1] sram_addr[2] sram_addr[3] sram_addr[4] sram_addr[5] sram_addr[6] sram_addr[7] sram_en sram_den sram_prechg sram_wen sram_ren sram_col_addr[0] sram_col_addr[1] sram_col_addr[2] sram_din[15] sram_dout[31] sram_din[14] sram_dout[30] sram_din[13] sram_dout[29] sram_din[12] sram_dout[28] sram_din[11] sram_dout[27] sram_din[10] sram_dout[26] sram_din[9] sram_dout[25] sram_din[8] sram_dout[24] sram_din[7] sram_dout[23] sram_din[6] sram_dout[22] sram_din[5] sram_dout[21] sram_din[4] sram_dout[20] sram_din[3] sram_dout[19] sram_din[2] sram_dout[18] sram_din[1] sram_dout[17] sram_din[0] sram_dout[16] sram_din[31] sram_dout[15] sram_din[30] sram_dout[14] sram_din[29] sram_dout[13] sram_din[28] sram_dout[12] sram_din[27] sram_dout[11] sram_din[26] sram_dout[10] sram_din[25] sram_dout[9] sram_din[24] sram_dout[8] sram_din[23] sram_dout[7] sram_din[22] sram_dout[6] sram_din[21] sram_dout[5] sram_din[20] sram_dout[4] sram_din[19] sram_dout[3] sram_din[18] sram_dout[2] sram_din[17] sram_dout[1] sram_din[16] sram_dout[0]} -fixedPin 1 -spreadType START -offsetStart 850 -offsetEnd 25 -pinWidth 0.5 -pinDepth 1.5 -spacing 0.5 -unit MICRON

setPinAssignMode -pinEditInBatch false
```

### Step 4: Power Structure

```tcl
addRing -nets {VDD VSS} -type core_rings -follow core -layer {top METAL_5 bottom METAL_5 left METAL_4 right METAL_4} -width {top 2.6 bottom 2.6 left 2.6 right 2.6} -spacing {top 5 bottom 5 left 5 right 5} -offset {top 0.2 bottom 0.2 left 0.2 right 0.2}

addStripe -nets {VDD VSS} -layer METAL_4 -direction vertical -width 2.6 -spacing 26 -set_to_set_distance 100 -start_from left

sroute -connect {corePin floatingStripe} -layerChangeRange {METAL_1 METAL_6} -nets {VDD VSS} -allowJogging 1 -allowLayerChange 1

saveDesign checkpoint_after_power_v7.enc
```

### Step 5: Placement

```tcl
place_design
```

Expect ~5 minutes. Verify 100% instances placed, no ERROR.

### Step 6: Pre-CTS Timing + Optimization

```tcl
timeDesign -preCTS
optDesign -preCTS
saveDesign checkpoint_after_placeopt_v7.enc
```

Expect ~8 minutes for optDesign. Goal: WNS > 0, max_cap and max_tran violating = 0.

### Step 7: Clock Tree Synthesis + Post-CTS Setup Opt

```tcl
create_ccopt_clock_tree_spec
set_ccopt_property target_max_trans 0.75
set_ccopt_property target_skew 0.25
setMultiCpuUsage -localCpu 8
clock_opt_design
```

Expect ~3-10 minutes. Goal: WNS still > 0 (will drop from pre-CTS by ~0.5ns due to clock insertion delay).

### Step 8: Post-CTS Timing + Hold Fixing (v5 pattern)

```tcl
# Check post-CTS timing first
timeDesign -postCTS
timeDesign -postCTS -hold

# First hold fix pass — tight target
setOptMode -holdTargetSlack 0.08 -holdFixingCells {buf_1 buf_2 buf_4} -maxDensity 0.72
optDesign -postCTS -hold

# Second hold fix pass — looser target, higher density allowed
setOptMode -holdTargetSlack 0.20 -holdFixingCells {buf_1 buf_2 buf_4} -maxDensity 0.75
optDesign -postCTS -hold

saveDesign checkpoint_after_cts_hold_v7.enc
```

### Step 9: Global + Detail Routing

```tcl
# Multi-cut via effort high (used in v5)
setNanoRouteMode -route_detail_use_multi_cut_via_effort high

routeDesign
saveDesign checkpoint_after_route_v7.enc
```

Expect 20-60 minutes depending on congestion. Watch for DRC count at end — should be single digits ideally.

### Step 10: Post-Route Timing + Optimization

```tcl
# Turn off clock uncertainty once route is done (v5 did this)
all_constraint_modes -active
set_interactive_constraint_modes [all_constraint_modes -active]
set_clock_uncertainty 0 [all_clocks]

# Enable OCV analysis mode (more accurate for post-route)
setAnalysisMode -analysisType onChipVariation -cppr both

# Check final timing
timeDesign -postRoute
timeDesign -postRoute -hold

# Post-route DRV opt
setOptMode -fixCap true -fixTran true -fixFanoutLoad false
optDesign -postRoute -drv

# Verify
verify_drc
verify_connectivity

saveDesign checkpoint_after_route_v7.enc
```

### Step 11: Export DEF/GDS

```tcl
# Netlist (post-route Verilog)
saveNetlist core_top_pnr_v7.v

# DEF (legacy single-file)
defOut core_top_pnr_v7.def

# DEF (full floorplan + routing + netlist for signoff)
defOut -floorplan -routing -netlist core_top_pnr_routed_v7.def

# GDS — use the QRC layermap (v5 used tsmc18_qrc.layermap not tsmc18.layermap)
streamOut core_top_pnr_v7.gds \
  -mapFile /home/home3/team2chips2026/qrc/tsmc18_qrc.layermap \
  -libName DesignLib -units 1000 -mode ALL

saveDesign checkpoint_final_v7.enc
```

### Step 12: Exit

```tcl
exit
```

Answer `no` to save prompt if asked (checkpoints are already saved explicitly).

---

## 3. Calibre Signoff (outside Innovus)

Once Innovus exports GDS/DEF, run in a separate shell:

```bash
cd /home/home3/team2chips2026/calibre
# Adjust rule deck paths as needed per your team's setup
calibre -drc -hier tsmc18_drc.runset
calibre -drc -hier tsmc18_antenna.runset
calibre -lvs -hier tsmc18_lvs.runset
```

Check DRC/antenna violation counts. Compare against v5's 836 antenna violations baseline.

---

## 4. Reference: key files and their purposes

| File | Purpose | Change vs v5 |
|---|---|---|
| `lef_v7/tech_v2_qrc.lef` | Technology LEF with QRC-style layer names | Regenerated from source (same content as v5) |
| `lef_v7/team2stdcells_final_wSideArea_patched_qrc.lef` | Stdcells with antenna patch applied | **NEW** — 125 antenna attributes added by `lef_patch_antenna.py` (auto-discovery mode) |
| `mmmc.tcl` | MMMC setup | Unchanged from v5 |
| `core_top_mapped.v` | Post-synth netlist | Unchanged from v5 |
| `core_top_pnr.sdc` | Timing constraints | Unchanged from v5 |
| `lef_patch_antenna.py` | The patcher script itself | **NEW** — auto-discovers missing antenna attrs per Innovus rule: every output pin needs GATEAREA, every input pin needs DIFFAREA |

---

## 5. If something goes wrong

### Restore from last good checkpoint
```tcl
restoreDesign /home/home3/team2chips2026/innovus_pnr/min_core_v5/checkpoint_after_<stage>_v7.enc.dat core_top
```

### Start over completely
Exit Innovus, relaunch, run Step 0 + Step 1 fresh.

### If Calibre shows antenna violations
The patcher put same-cell donor values (abstraction-equivalent, not physically measured). If Calibre antenna is still high, the real fix is to get your teammate to re-run abstracta with complementary antenna extraction enabled (the GATEAREA-from-downstream-fanin / DIFFAREA-from-upstream-driver mode). The patcher is a workaround, not a correct extraction.