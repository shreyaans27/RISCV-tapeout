// ============================================================
// rom_ctrl.v — 16KB ROM controller
//
// ROM structure: 256 WL × 16 column groups × 2 bits/cell = 32 bits/read
//
// Address mapping (byte address offset from 0x20000000):
//   offset[9:2]   → WL address (8 bits, 256 word lines)
//   offset[13:10]  → column mux address (4 bits, 16 groups)
//   offset[1:0]   → byte lane (for lb)
//
// Data pattern:
//   pattern = (wl_addr + col_mux_addr) % 4
//   0 → 0x00000000
//   1 → 0x55555555
//   2 → 0xAAAAAAAA
//   3 → 0xFFFFFFFF
//
// Single-cycle read. Read-only (writes ignored).
// ============================================================

module rom_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        req_valid,
    output wire        req_ready,
    input  wire [31:0] req_addr,
    output reg         resp_valid,
    output reg  [31:0] resp_rdata
);

    // Address decode
    wire [7:0] wl_addr  = req_addr[9:2];    // 256 word lines
    wire [3:0] col_addr = req_addr[13:10];   // 16 column mux groups

    // Pattern computation
    wire [1:0] pattern = (wl_addr[1:0] + col_addr[1:0]);

    // Pattern to data mapping
    reg [31:0] rom_data;
    always @(*) begin
        case (pattern)
            2'd0: rom_data = 32'h00000000;
            2'd1: rom_data = 32'h55555555;
            2'd2: rom_data = 32'hAAAAAAAA;
            2'd3: rom_data = 32'hFFFFFFFF;
        endcase
    end

    // Always ready
    assign req_ready = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_valid <= 1'b0;
            resp_rdata <= 32'h0;
        end else if (req_valid && req_ready) begin
            resp_valid <= 1'b1;
            resp_rdata <= rom_data;
        end else begin
            resp_valid <= 1'b0;
        end
    end

endmodule
