// ============================================================
// rom_16kb.v — 16KB ROM wrapper
//
// Behavioral model for simulation.
// For tapeout: replace internals with ROM macro instance.
//
// ROM structure: 256 WL × 16 col_mux × 32 bits = 16KB
// Data pattern: (wl_addr[1:0] + col_addr[1:0]) % 4
//   0 → 0x00000000
//   1 → 0x55555555
//   2 → 0xAAAAAAAA
//   3 → 0xFFFFFFFF
//
// Single-port read-only interface:
//   - 4096 words × 32 bits = 16KB
//   - addr[7:0]  = WL address (256 word lines)
//   - addr[11:8] = column mux address (16 groups)
//   - Single-cycle read
// ============================================================

module rom_16kb (
    input  wire        clk,
    input  wire [11:0] addr,       // 12-bit word address (4096 entries)
    output reg  [31:0] rdata       // read data (1-cycle latency)
);

    // Address decode
    wire [7:0] wl_addr  = addr[7:0];    // word line
    wire [3:0] col_addr = addr[11:8];   // column mux

    // Pattern computation
    wire [1:0] pattern = wl_addr[1:0] + col_addr[1:0];

    // Combinational pattern lookup
    reg [31:0] rom_data;
    always @(*) begin
        case (pattern)
            2'd0: rom_data = 32'h00000000;
            2'd1: rom_data = 32'h55555555;
            2'd2: rom_data = 32'hAAAAAAAA;
            2'd3: rom_data = 32'hFFFFFFFF;
        endcase
    end

    // Synchronous read output
    always @(posedge clk) begin
        rdata <= rom_data;
    end

endmodule
