// ============================================================
// rom_ctrl.v — 16KB ROM controller
//
// Bus interface logic + ROM wrapper instantiation.
// Address: 0x20000000 - 0x20003FFF (16KB)
// Read-only (writes ignored).
//
// Address mapping from bus byte address:
//   byte_addr[9:2]   → WL address (8 bits)  → rom_addr[7:0]
//   byte_addr[13:10]  → column mux (4 bits)  → rom_addr[11:8]
// ============================================================

module rom_ctrl (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        req_valid,
    output wire        req_ready,
    input  wire [31:0] req_addr,
    output reg         resp_valid,
    output wire [31:0] resp_rdata
);

    // Address mapping: bus byte addr → ROM word addr
    // WL = byte_addr[9:2], COL = byte_addr[13:10]
    wire [11:0] rom_addr = {req_addr[13:10], req_addr[9:2]};

    // Always ready
    assign req_ready = 1'b1;

    // ROM instance
    rom_16kb u_rom (
        .clk   (clk),
        .addr  (rom_addr),
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
