# min_core_v18 — Complete Innovus PnR Command Script
# LEF: lef/tech_v2_qrc.lef + lef/team2stdcells_pinUpdates_wSideArea_qrc.lef
# April 19, 2026 | team2chips2026
#
# HOW TO RUN:
# 1. Launch Innovus:
#    source /home/home3/team2chips2026/innovus_pnr/launch_innovus.sh
# 2. cd to working directory:
#    cd /home/home3/team2chips2026/innovus_pnr/min_core_v5/
# 3. Copy script there and source it:
#    source pnr_v18.tcl

# ============================================================
# STEP 1 — DESIGN INIT
# ============================================================

set_global _enable_mmmc_by_default_flow $CTE::mmmc_default
suppressMessage ENCEXT-2799

setMessageLimit 10000 

set init_lef_file {lef/tech_v2_no_M6_qrc.lef lef/team2stdcellsV4_qrc.lef}
set init_mmmc_file mmmc.tcl
set init_verilog core_top_mapped.v
set init_top_cell core_top
set init_pwr_net VDD
set init_gnd_net VSS
init_design

# ============================================================
# STEP 2 — GLOBAL NET CONNECT & FLOORPLAN
# ============================================================

globalNetConnect VDD -type pgpin -pin VDD -inst *
globalNetConnect VSS -type pgpin -pin VSS -inst *

floorPlan -coreMarginsBy die -site core -d 1030 1100 15 15 15 15

# ============================================================
# STEP 3 — PIN PLACEMENT
# ============================================================

setPinAssignMode -pinEditInBatch true

# North — ROM interface (METAL_2)
editPin -side N -layer METAL_2 \
   -pin {rom_dout[31] rom_dout[30] rom_dout[29] rom_dout[28] \
         rom_dout[27] rom_dout[26] rom_dout[25] rom_dout[24] \
         rom_dout[23] rom_dout[22] rom_dout[21] rom_dout[20] \
         rom_dout[19] rom_dout[18] rom_dout[17] rom_dout[16] \
         rom_dout[15] rom_dout[14] rom_dout[13] rom_dout[12] \
         rom_dout[11] rom_dout[10] rom_dout[9]  rom_dout[8] \
         rom_dout[7]  rom_dout[6]  rom_dout[5]  rom_dout[4] \
         rom_dout[3]  rom_dout[2]  rom_dout[1]  rom_dout[0] \
         rom_wl_addr[0] rom_wl_addr[1] rom_wl_addr[2] rom_wl_addr[3] \
         rom_wl_addr[4] rom_wl_addr[5] rom_wl_addr[6] rom_wl_addr[7] \
         rom_col_in[0] rom_col_in[1] rom_col_in[2] rom_col_in[3] \
         rom_wlen rom_preen rom_saen} \
   -fixedPin 1 -spreadType CENTER \
   -pinWidth 0.5 -pinDepth 1.5 -spacing 1 -unit MICRON

# West — Debug (METAL_3)
editPin -side W -layer METAL_3 \
   -pin {debug_pc[0]  debug_pc[1]  debug_pc[2]  debug_pc[3] \
         debug_pc[4]  debug_pc[5]  debug_pc[6]  debug_pc[7] \
         debug_pc[8]  debug_pc[9]  debug_pc[10] debug_pc[11] \
         debug_pc[12] debug_pc[13] debug_pc[14] debug_pc[15] \
         debug_pc[16] debug_pc[17] debug_pc[18] debug_pc[19] \
         debug_pc[20] debug_pc[21] debug_pc[22] debug_pc[23] \
         debug_pc[24] debug_pc[25] debug_pc[26] debug_pc[27] \
         debug_pc[28] debug_pc[29] debug_pc[30] debug_pc[31] \
         debug_resp_valid} \
   -fixedPin 1 -spreadType CENTER \
   -pinWidth 0.5 -pinDepth 1.5 -spacing 3 -unit MICRON

# South — Control & JTAG (METAL_3)
editPin -side S -layer METAL_3 \
   -pin {pad_clk rst_n jtag_tck jtag_tms jtag_tdi jtag_tdo} \
   -fixedPin 1 -spreadType CENTER \
   -pinWidth 1.0 -pinDepth 1.5 -spacing 5 -unit MICRON

# East — SRAM interface (METAL_3)
editPin -edge 2 -layer METAL_5 \
   -pin {sram_addr[1] sram_addr[3] sram_addr[5] sram_addr[7] \
         sram_den sram_ren \
         sram_col_addr[1] \
         sram_dout[31] sram_dout[30] sram_dout[29] sram_dout[28] \
         sram_dout[27] sram_dout[26] sram_dout[25] sram_dout[24] \
         sram_dout[23] sram_dout[22] sram_dout[21] sram_dout[20] \
         sram_dout[19] sram_dout[18] sram_dout[17] sram_dout[16] \
         sram_dout[15] sram_dout[14] sram_dout[13] sram_dout[12] \
         sram_dout[11] sram_dout[10] sram_dout[9]  sram_dout[8] \
         sram_dout[7]  sram_dout[6]  sram_dout[5]  sram_dout[4] \
         sram_dout[3]  sram_dout[2]  sram_dout[1]  sram_dout[0]} \
   -fixedPin 1 -spreadType START -offsetStart 753 -offsetEnd 25 \
   -pinWidth 0.5 -pinDepth 1.5 -spacing 6.0 -unit MICRON

editPin -edge 2 -layer METAL_3 \
   -pin {sram_addr[0] sram_addr[2] sram_addr[4] sram_addr[6] \
         sram_en sram_prechg sram_wen \
         sram_col_addr[0] sram_col_addr[2] \
         sram_din[15] sram_din[14] sram_din[13] sram_din[12] \
         sram_din[11] sram_din[10] sram_din[9]  sram_din[8] \
         sram_din[7]  sram_din[6]  sram_din[5]  sram_din[4] \
         sram_din[3]  sram_din[2]  sram_din[1]  sram_din[0] \
         sram_din[31] sram_din[30] sram_din[29] sram_din[28] \
         sram_din[27] sram_din[26] sram_din[25] sram_din[24] \
         sram_din[23] sram_din[22] sram_din[21] sram_din[20] \
         sram_din[19] sram_din[18] sram_din[17] sram_din[16]} \
   -fixedPin 1 -spreadType START -offsetStart 750 -offsetEnd 25 \
   -pinWidth 0.5 -pinDepth 1.5 -spacing 6.0 -unit MICRON

setPinAssignMode -pinEditInBatch false

# ============================================================
# STEP 4 — POWER PLANNINGoptDesign -preCTS
# ============================================================

addRing -nets {VDD VSS} \
  -type core_rings -follow core \
  -layer {top METAL_5 bottom METAL_5 left METAL_4 right METAL_4} \
  -width {top 2.6 bottom 2.6 left 2.6 right 2.6} \
  -spacing {top 5 bottom 5 left 5 right 5} \
  -offset {top 0.2 bottom 0.2 left 0.2 right 0.2}

addStripe -nets {VDD VSS} \
  -layer METAL_4 -direction vertical \
  -width 2.6 -spacing 26 \
  -set_to_set_distance 100 \
  -start_from left

sroute -connect {corePin floatingStripe} \
  -layerChangeRange {METAL_1 METAL_6} \
  -nets {VDD VSS} \
  -allowJogging 1 -allowLayerChange 1

saveDesign checkpoint_after_power_v18.enc

# ============================================================
# STEP 5 — PLACEMENT
# ============================================================

place_design
saveDesign checkpoint_after_place_v18.enc

timeDesign -preCTS
timeDesign -preCTS -hold

optDesign -preCTS
saveDesign checkpoint_after_placeopt_v18.enc

# ============================================================
# STEP 6 — CTS
# ============================================================

create_ccopt_clock_tree_spec
set_ccopt_property target_max_trans 0.75
set_ccopt_property target_skew 0.25
setMultiCpuUsage -localCpu 8
clock_opt_design

timeDesign -postCTS
timeDesign -postCTS -hold

setOptMode -holdTargetSlack 0.08 \
  -holdFixingCells {buf_1 buf_2 buf_4} \
  -maxDensity 0.72
optDesign -postCTS -hold

saveDesign checkpoint_after_cts_hold_v18.enc

# ============================================================
# STEP 7 — REMOVE CLOCK UNCERTAINTY POST-CTS
# ============================================================

set_interactive_constraint_modes [all_constraint_modes -active]
set_clock_uncertainty 0 [all_clocks]

# ============================================================
# STEP 8 — ROUTING
# ============================================================

setNanoRouteMode -route_detail_use_multi_cut_via_effort high
routeDesign
saveDesign checkpoint_after_route_v18.enc

# ============================================================
# STEP 9 — POST-ROUTE TIMING ANALYSIS
# ============================================================

setAnalysisMode -analysisType onChipVariation -cppr both
timeDesign -postRoute
timeDesign -postRoute -hold

# ============================================================
# STEP 10 — POST-ROUTE OPTIMIZATION (DRV only)
# ============================================================

setOptMode -fixCap true -fixTran true -fixFanoutLoad false
optDesign -postRoute -drv

verify_drc
verify_connectivity

saveDesign checkpoint_final_v18.enc

# ============================================================
# STEP 11 — EXPORT
# ============================================================

# saveNetlist -phys core_top_pnr_v18.v

# defOut core_top_pnr_v18.def

# defOut -floorplan -routing -netlist core_top_pnr_v18_routed.def

# streamOut core_top_pnr_v18.gds \
#   -mapFile /home/home3/team2chips2026/qrc/tsmc18_qrc.layermap \
#   -libName DesignLib -units 1000 -mode ALL


# ============================================================
# STEP 12 — BACKWARD RENAME FOR VIRTUOSO (run in terminal)
# ============================================================
# python3 /home/home3/team2chips2026/qrc/rename_layers.py --backward \
#   core_top_pnr_v14_routed.def \
#   /home/home3/team2chips2026/TSMC_180_work/core_top_pnr_v14_virtuoso.def
#
# Verify:
# grep "^NETS" /home/home3/team2chips2026/TSMC_180_work/core_top_pnr_v13_virtuoso.def

# ============================================================
# STEP 13 — VIRTUOSO DEF IMPORT (GUI)
# File → Import → DEF
#   DEF File:            .../TSMC_180_work/core_top_pnr_v18_virtuoso.def
#   Library:             team2chips2026_FINAL
#   Cell:                core_top_v18
#   View:                layout
#   Component View List: layout
#   Master Libraries:    StandardCellLibv2
#   Layer Map:           .../TSMC_180_work/defin_simple.layermap
#   Tech Refs:           tsmc18
#   Overwrite:           checked
# ============================================================