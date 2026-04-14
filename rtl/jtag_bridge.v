// ============================================================
// jtag_bridge.v — Minimal JTAG-to-bus bridge (STUB)
//
// For simulation: core_rst_n directly follows rst_n
// No JTAG activity — core runs immediately after reset.
// Full JTAG TAP implementation added later for tapeout.
// ============================================================

module jtag_bridge (
    input  wire        clk,
    input  wire        rst_n,

    // JTAG pins
    input  wire        jtag_tck,
    input  wire        jtag_tms,
    input  wire        jtag_tdi,
    output wire        jtag_tdo,

    // Core reset control
    output wire        core_rst_n,

    // Bus master interface (inactive for now)
    output wire        req_valid,
    input  wire        req_ready,
    output wire [31:0] req_addr,
    output wire [31:0] req_wdata,
    output wire [3:0]  req_wmask,
    output wire        req_wen,
    input  wire        resp_valid,
    input  wire [31:0] resp_rdata
);

    // Stub: core reset follows system reset
    assign core_rst_n = rst_n;

    // Stub: no bus activity
    assign req_valid = 1'b0;
    assign req_addr  = 32'h0;
    assign req_wdata = 32'h0;
    assign req_wmask = 4'h0;
    assign req_wen   = 1'b0;

    // JTAG TDO — idle
    assign jtag_tdo = 1'b0;

endmodule
