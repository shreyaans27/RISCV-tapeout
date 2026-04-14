// ============================================================
// sram_ctrl.v — 8KB SRAM controller
//
// Behavioral model for simulation.
// For tapeout: replace mem array with SRAM macro.
//
// Address: 0x08000000 - 0x08001FFF (8KB)
// Supports byte-masked writes (wmask).
// Single-cycle read/write.
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
    output reg  [31:0] resp_rdata
);

    // 8KB = 2048 words of 32 bits
    reg [31:0] mem [0:2047];

    // Word address from byte address
    wire [10:0] word_addr = req_addr[12:2];

    // Always ready to accept
    assign req_ready = 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_valid <= 1'b0;
            resp_rdata <= 32'h0;
        end else if (req_valid && req_ready) begin
            resp_valid <= 1'b1;
            if (req_wen) begin
                // Byte-masked write
                if (req_wmask[0]) mem[word_addr][ 7: 0] <= req_wdata[ 7: 0];
                if (req_wmask[1]) mem[word_addr][15: 8] <= req_wdata[15: 8];
                if (req_wmask[2]) mem[word_addr][23:16] <= req_wdata[23:16];
                if (req_wmask[3]) mem[word_addr][31:24] <= req_wdata[31:24];
                resp_rdata <= 32'h0;
            end else begin
                // Read
                resp_rdata <= mem[word_addr];
            end
        end else begin
            resp_valid <= 1'b0;
        end
    end

    // --------------------------------------------------------
    // Firmware loading (simulation only)
    // --------------------------------------------------------
    task load_hex(input [256*8-1:0] filename);
        $readmemh(filename, mem);
    endtask

endmodule
