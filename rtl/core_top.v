// ============================================================
// core_top.v — Minimal ML Inference SoC Top Level
//
// Clocking:
//   pad_clk (100MHz) → clk_div → clk_50 (mem ctrl timing) + clk_25 (core)
//
// Memory Map:
//   0x08000000 - 0x08001FFF : 8KB SRAM
//   0x20000000 - 0x20003FFF : 16KB ROM
//
// SRAM and ROM macros are EXTERNAL — not in this RTL.
// Controllers output raw control signals to top-level ports.
// These get manually routed to macro pads during P&R.
// ============================================================

module core_top (
    input  wire        pad_clk,     // 200 MHz pad clock
    input  wire        rst_n,       // active-low reset

    // JTAG interface
    input  wire        jtag_tck,
    input  wire        jtag_tms,
    input  wire        jtag_tdi,
    output wire        jtag_tdo,

    // SRAM macro pins (directly to pads)
    output wire        sram_den,        // decoder enable (active high)
    output wire [7:0]  sram_addr,       // row address A<7:0>
    output wire [2:0]  sram_col_addr,   // column mux address C<2:0>
    output wire        sram_prechg,     // precharge (active low)
    output wire        sram_ren,        // read/sense enable
    output wire        sram_wen,        // write enable
    output wire        sram_en,         // column mux enable
    output wire [31:0] sram_din,        // data in
    input  wire [31:0] sram_dout,       // data out

    // ROM macro pins (directly to pads)
    output wire [7:0]  rom_wl_addr,
    output wire [3:0]  rom_col_in,
    output wire        rom_preen,
    output wire        rom_wlen,
    output wire        rom_saen,
    input  wire [31:0] rom_dout,

    // Debug outputs (anchor pipeline for synthesis)
    output wire [31:0] debug_pc,
    output wire        debug_resp_valid
);

    // --------------------------------------------------------
    // Clock generation
    // --------------------------------------------------------
    wire clk_50;
    wire clk_25;

    clk_div u_clk_div (
        .pad_clk (pad_clk),
        .rst_n   (rst_n),
        .clk_50  (clk_50),
        .clk_25  (clk_25)
    );

    // --------------------------------------------------------
    // Core bus master signals
    // --------------------------------------------------------
    wire        core_req_valid;
    wire        core_req_ready;
    wire [31:0] core_req_addr;
    wire [31:0] core_req_wdata;
    wire [3:0]  core_req_wmask;
    wire        core_req_wen;
    wire        core_resp_valid;
    wire [31:0] core_resp_rdata;

    // --------------------------------------------------------
    // JTAG bus master signals
    // --------------------------------------------------------
    wire        jtag_req_valid;
    wire        jtag_req_ready;
    wire [31:0] jtag_req_addr;
    wire [31:0] jtag_req_wdata;
    wire [3:0]  jtag_req_wmask;
    wire        jtag_req_wen;
    wire        jtag_resp_valid;
    wire [31:0] jtag_resp_rdata;

    // --------------------------------------------------------
    // SRAM slave bus signals
    // --------------------------------------------------------
    wire        sram_bus_req_valid;
    wire        sram_bus_req_ready;
    wire [31:0] sram_bus_req_addr;
    wire [31:0] sram_bus_req_wdata;
    wire [3:0]  sram_bus_req_wmask;
    wire        sram_bus_req_wen;
    wire        sram_bus_resp_valid;
    wire [31:0] sram_bus_resp_rdata;

    // --------------------------------------------------------
    // ROM slave bus signals
    // --------------------------------------------------------
    wire        rom_bus_req_valid;
    wire        rom_bus_req_ready;
    wire [31:0] rom_bus_req_addr;
    wire        rom_bus_req_wen;
    wire        rom_bus_resp_valid;
    wire [31:0] rom_bus_resp_rdata;

    // --------------------------------------------------------
    // Core reset (controlled by JTAG bridge)
    // --------------------------------------------------------
    wire core_rst_n;
    wire core_clk_en;

    // --------------------------------------------------------
    // Debug outputs
    // --------------------------------------------------------
    wire [31:0] debug_pc_internal = core_req_addr;
    assign debug_pc         = debug_pc_internal;
    assign debug_resp_valid = core_resp_valid;

    // --------------------------------------------------------
    // Clock gating for core (JTAG single-step support)
    // When core_clk_en=0, core is frozen
    wire clk_core_gated;
    reg clk_gate_latch;
    /* verilator lint_off LATCH */
    always @(*) begin
        if (!clk_25)
            clk_gate_latch = core_clk_en;
    end
    /* verilator lint_on LATCH */
    assign clk_core_gated = clk_25 & clk_gate_latch;

    // RV32IM Core (clk_25, gated)
    // --------------------------------------------------------
    rv32im_core u_core (
        .clk            (clk_core_gated),
        .rst_n          (core_rst_n),
        .req_valid      (core_req_valid),
        .req_ready      (core_req_ready),
        .req_addr       (core_req_addr),
        .req_wdata      (core_req_wdata),
        .req_wmask      (core_req_wmask),
        .req_wen        (core_req_wen),
        .resp_valid     (core_resp_valid),
        .resp_rdata     (core_resp_rdata)
    );

    // --------------------------------------------------------
    // JTAG Bridge (clk_25)
    // --------------------------------------------------------
    jtag_bridge u_jtag (
        .clk            (clk_25),
        .rst_n          (rst_n),
        .jtag_tck       (jtag_tck),
        .jtag_tms       (jtag_tms),
        .jtag_tdi       (jtag_tdi),
        .jtag_tdo       (jtag_tdo),
        .core_rst_n     (core_rst_n),
        .core_clk_en    (core_clk_en),
        .req_valid      (jtag_req_valid),
        .req_ready      (jtag_req_ready),
        .req_addr       (jtag_req_addr),
        .req_wdata      (jtag_req_wdata),
        .req_wmask      (jtag_req_wmask),
        .req_wen        (jtag_req_wen),
        .resp_valid     (jtag_resp_valid),
        .resp_rdata     (jtag_resp_rdata),
        .debug_pc       (debug_pc_internal)
    );

    // --------------------------------------------------------
    // Bus Crossbar (clk_25)
    // --------------------------------------------------------
    bus_xbar u_xbar (
        .clk            (clk_25),
        .rst_n          (rst_n),
        .m0_req_valid   (core_req_valid),
        .m0_req_ready   (core_req_ready),
        .m0_req_addr    (core_req_addr),
        .m0_req_wdata   (core_req_wdata),
        .m0_req_wmask   (core_req_wmask),
        .m0_req_wen     (core_req_wen),
        .m0_resp_valid  (core_resp_valid),
        .m0_resp_rdata  (core_resp_rdata),
        .m1_req_valid   (jtag_req_valid),
        .m1_req_ready   (jtag_req_ready),
        .m1_req_addr    (jtag_req_addr),
        .m1_req_wdata   (jtag_req_wdata),
        .m1_req_wmask   (jtag_req_wmask),
        .m1_req_wen     (jtag_req_wen),
        .m1_resp_valid  (jtag_resp_valid),
        .m1_resp_rdata  (jtag_resp_rdata),
        .s0_req_valid   (sram_bus_req_valid),
        .s0_req_ready   (sram_bus_req_ready),
        .s0_req_addr    (sram_bus_req_addr),
        .s0_req_wdata   (sram_bus_req_wdata),
        .s0_req_wmask   (sram_bus_req_wmask),
        .s0_req_wen     (sram_bus_req_wen),
        .s0_resp_valid  (sram_bus_resp_valid),
        .s0_resp_rdata  (sram_bus_resp_rdata),
        .s1_req_valid   (rom_bus_req_valid),
        .s1_req_ready   (rom_bus_req_ready),
        .s1_req_addr    (rom_bus_req_addr),
        .s1_req_wdata   (),             // ROM is read-only
        .s1_req_wmask   (),
        .s1_req_wen     (rom_bus_req_wen),
        .s1_resp_valid  (rom_bus_resp_valid),
        .s1_resp_rdata  (rom_bus_resp_rdata)
    );

    // --------------------------------------------------------
    // SRAM Controller (clk_25 bus + pad_clk timing)
    // --------------------------------------------------------
    sram_ctrl u_sram (
        .clk            (clk_25),
        .clk_fast       (pad_clk),
        .rst_n          (rst_n),
        // Bus side
        .req_valid      (sram_bus_req_valid),
        .req_ready      (sram_bus_req_ready),
        .req_addr       (sram_bus_req_addr),
        .req_wdata      (sram_bus_req_wdata),
        .req_wmask      (sram_bus_req_wmask),
        .req_wen        (sram_bus_req_wen),
        .resp_valid     (sram_bus_resp_valid),
        .resp_rdata     (sram_bus_resp_rdata),
        // SRAM macro pins
        .sram_den       (sram_den),
        .sram_addr      (sram_addr),
        .sram_col_addr  (sram_col_addr),
        .sram_prechg    (sram_prechg),
        .sram_ren       (sram_ren),
        .sram_wen       (sram_wen),
        .sram_en        (sram_en),
        .sram_din       (sram_din),
        .sram_dout      (sram_dout)
    );

    // --------------------------------------------------------
    // ROM Controller (clk_25 bus + pad_clk timing)
    // --------------------------------------------------------
    rom_ctrl u_rom (
        .clk            (clk_25),
        .clk_fast       (pad_clk),
        .rst_n          (rst_n),
        // Bus side
        .req_valid      (rom_bus_req_valid),
        .req_ready      (rom_bus_req_ready),
        .req_addr       (rom_bus_req_addr),
        .resp_valid     (rom_bus_resp_valid),
        .resp_rdata     (rom_bus_resp_rdata),
        // ROM macro pins
        .rom_wl_addr    (rom_wl_addr),
        .rom_col_in     (rom_col_in),
        .rom_preen      (rom_preen),
        .rom_wlen       (rom_wlen),
        .rom_saen       (rom_saen),
        .rom_dout       (rom_dout)
    );

endmodule
