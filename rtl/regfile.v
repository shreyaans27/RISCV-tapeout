// ============================================================
// regfile.v — RV32I Register File
//
// 32 registers × 32 bits. x0 is hardwired to 0.
// 2 read ports (rs1, rs2), 1 write port (rd).
// Write-first: if reading and writing same register, read returns new value.
// ============================================================

module regfile (
    input  wire        clk,
    input  wire        rst_n,

    // Read port 1
    input  wire [4:0]  rs1_addr,
    output wire [31:0] rs1_data,

    // Read port 2
    input  wire [4:0]  rs2_addr,
    output wire [31:0] rs2_data,

    // Write port
    input  wire        wr_en,
    input  wire [4:0]  wr_addr,
    input  wire [31:0] wr_data
);

    reg [31:0] regs [1:31];  // x1-x31, x0 is always 0

    // Read with write-forwarding
    assign rs1_data = (rs1_addr == 5'd0) ? 32'h0 :
                      (wr_en && wr_addr == rs1_addr) ? wr_data :
                      regs[rs1_addr];

    assign rs2_data = (rs2_addr == 5'd0) ? 32'h0 :
                      (wr_en && wr_addr == rs2_addr) ? wr_data :
                      regs[rs2_addr];

    // Write
    always @(posedge clk) begin
        if (wr_en && wr_addr != 5'd0) begin
            regs[wr_addr] <= wr_data;
        end
    end

endmodule
