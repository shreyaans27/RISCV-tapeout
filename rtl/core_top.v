// ============================================================
// core_top.v — Minimal ML Inference SoC Top Level
// 
// Architecture:
//   RV32IM core + DotProd4 + JTAG bridge
//   Simple bus: 2 masters (core, jtag) → 2 slaves (sram, rom)
//
// Memory Map:
//   0x08000000 - 0x08001FFF : 8KB SRAM (firmware + data)
//   0x20000000 - 0x20003FFF : 16KB ROM (weights)
// ============================================================

module core_top (
    input  wire        clk,
    input  wire        rst_n,      // active-low reset

    // JTAG interface
    input  wire        jtag_tck,
    input  wire        jtag_tms,
    input  wire        jtag_tdi,
    output wire        jtag_tdo
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
    // SRAM slave signals
    // --------------------------------------------------------
    wire        sram_req_valid;
    wire        sram_req_ready;
    wire [31:0] sram_req_addr;
    wire [31:0] sram_req_wdata;
    wire [3:0]  sram_req_wmask;
    wire        sram_req_wen;
    wire        sram_resp_valid;
    wire [31:0] sram_resp_rdata;

    // --------------------------------------------------------
    // ROM slave signals
    // --------------------------------------------------------
    wire        rom_req_valid;
    wire        rom_req_ready;
    wire [31:0] rom_req_addr;
    wire [31:0] rom_req_wdata;
    wire [3:0]  rom_req_wmask;
    wire        rom_req_wen;
    wire        rom_resp_valid;
    wire [31:0] rom_resp_rdata;

    // --------------------------------------------------------
    // Core reset (controlled by JTAG bridge)
    // --------------------------------------------------------
    wire        core_rst_n;

    // --------------------------------------------------------
    // RV32IM Core + DotProd4
    // --------------------------------------------------------
    rv32im_core u_core (
        .clk            (clk),
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
    // JTAG Bridge
    // --------------------------------------------------------
    jtag_bridge u_jtag (
        .clk            (clk),
        .rst_n          (rst_n),
        .jtag_tck       (jtag_tck),
        .jtag_tms       (jtag_tms),
        .jtag_tdi       (jtag_tdi),
        .jtag_tdo       (jtag_tdo),
        .core_rst_n     (core_rst_n),
        .req_valid      (jtag_req_valid),
        .req_ready      (jtag_req_ready),
        .req_addr       (jtag_req_addr),
        .req_wdata      (jtag_req_wdata),
        .req_wmask      (jtag_req_wmask),
        .req_wen        (jtag_req_wen),
        .resp_valid     (jtag_resp_valid),
        .resp_rdata     (jtag_resp_rdata)
    );

    // --------------------------------------------------------
    // Bus Crossbar (2 masters → 2 slaves)
    // Address decode:
    //   0x08000000-0x08001FFF → SRAM
    //   0x20000000-0x20003FFF → ROM
    // --------------------------------------------------------
    bus_xbar u_xbar (
        .clk            (clk),
        .rst_n          (rst_n),

        // Master 0: Core
        .m0_req_valid   (core_req_valid),
        .m0_req_ready   (core_req_ready),
        .m0_req_addr    (core_req_addr),
        .m0_req_wdata   (core_req_wdata),
        .m0_req_wmask   (core_req_wmask),
        .m0_req_wen     (core_req_wen),
        .m0_resp_valid  (core_resp_valid),
        .m0_resp_rdata  (core_resp_rdata),

        // Master 1: JTAG
        .m1_req_valid   (jtag_req_valid),
        .m1_req_ready   (jtag_req_ready),
        .m1_req_addr    (jtag_req_addr),
        .m1_req_wdata   (jtag_req_wdata),
        .m1_req_wmask   (jtag_req_wmask),
        .m1_req_wen     (jtag_req_wen),
        .m1_resp_valid  (jtag_resp_valid),
        .m1_resp_rdata  (jtag_resp_rdata),

        // Slave 0: SRAM
        .s0_req_valid   (sram_req_valid),
        .s0_req_ready   (sram_req_ready),
        .s0_req_addr    (sram_req_addr),
        .s0_req_wdata   (sram_req_wdata),
        .s0_req_wmask   (sram_req_wmask),
        .s0_req_wen     (sram_req_wen),
        .s0_resp_valid  (sram_resp_valid),
        .s0_resp_rdata  (sram_resp_rdata),

        // Slave 1: ROM
        .s1_req_valid   (rom_req_valid),
        .s1_req_ready   (rom_req_ready),
        .s1_req_addr    (rom_req_addr),
        .s1_req_wdata   (rom_req_wdata),
        .s1_req_wmask   (rom_req_wmask),
        .s1_req_wen     (rom_req_wen),
        .s1_resp_valid  (rom_resp_valid),
        .s1_resp_rdata  (rom_resp_rdata)
    );

    // --------------------------------------------------------
    // SRAM (8KB @ 0x08000000) — behavioral for sim
    // --------------------------------------------------------
    sram_ctrl u_sram (
        .clk            (clk),
        .rst_n          (rst_n),
        .req_valid      (sram_req_valid),
        .req_ready      (sram_req_ready),
        .req_addr       (sram_req_addr),
        .req_wdata      (sram_req_wdata),
        .req_wmask      (sram_req_wmask),
        .req_wen        (sram_req_wen),
        .resp_valid     (sram_resp_valid),
        .resp_rdata     (sram_resp_rdata)
    );

    // --------------------------------------------------------
    // ROM (16KB @ 0x20000000) — deterministic pattern
    // --------------------------------------------------------
    rom_ctrl u_rom (
        .clk            (clk),
        .rst_n          (rst_n),
        .req_valid      (rom_req_valid),
        .req_ready      (rom_req_ready),
        .req_addr       (rom_req_addr),
        .resp_valid     (rom_resp_valid),
        .resp_rdata     (rom_resp_rdata)
    );

endmodule
