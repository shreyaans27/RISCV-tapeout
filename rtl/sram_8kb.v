// ============================================================
// sram_8kb.v — 8KB SRAM wrapper
//
// Behavioral model for simulation.
// For tapeout: replace internals with SRAM macro instance.
//
// Single-port SRAM interface:
//   - 2048 words × 32 bits = 8KB
//   - Single-cycle read/write
//   - Byte-level write enable (active high)
// ============================================================

module sram_8kb (
    input  wire        clk,
    input  wire        we,         // write enable
    input  wire [10:0] addr,       // 11-bit word address (2048 entries)
    input  wire [31:0] wdata,      // write data
    input  wire [3:0]  wmask,      // byte write mask (active high)
    output reg  [31:0] rdata       // read data (1-cycle latency)
);

    // Behavioral memory array
    reg [31:0] mem [0:2047];

    always @(posedge clk) begin
        if (we) begin
            if (wmask[0]) mem[addr][ 7: 0] <= wdata[ 7: 0];
            if (wmask[1]) mem[addr][15: 8] <= wdata[15: 8];
            if (wmask[2]) mem[addr][23:16] <= wdata[23:16];
            if (wmask[3]) mem[addr][31:24] <= wdata[31:24];
        end
        rdata <= mem[addr]; // synchronous read
    end

endmodule
