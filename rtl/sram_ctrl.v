// ============================================================
// sram_ctrl.v — 8KB SRAM controller
//
// Bus interface logic + SRAM wrapper instantiation.
// Address: 0x08000000 - 0x08001FFF (8KB)
// Supports byte-masked writes.
// ============================================================

module sram_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        req_valid,
    output wire        req_ready,
    input  wire [31:0] req_addr,
    input  wire [31:0] req_wdata,
    input  wire [3:0]  req_wmask,
    input  wire        req_wen,
    output reg         resp_valid,
    output wire [31:0] resp_rdata
);

    // Word address from byte address
    wire [10:0] word_addr = req_addr[12:2];

    // Always ready to accept
    assign req_ready = 1'b1;

    // SRAM write enable: valid request + write
    wire sram_we = req_valid && req_ready && req_wen;

    // SRAM instance
    sram_8kb u_sram (
        .clk   (clk),
        .we    (sram_we),
        .addr  (word_addr),
        .wdata (req_wdata),
        .wmask (req_wmask),
        .rdata (resp_rdata)
    );

    // Response valid — one cycle after request
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            resp_valid <= 1'b0;
        else
            resp_valid <= req_valid && req_ready;
    end

endmodule
