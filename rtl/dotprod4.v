// ============================================================
// dotprod4.v — 4× INT8 MAC unit
//
// custom-0 opcode (0x0B), funct7 selects operation:
//   funct7=0x00  DOTPROD4  — 4× INT8 multiply-accumulate
//   funct7=0x01  ACC_RESET — reset accumulator to 0
//   funct7=0x02  ACC_READ  — read accumulator value
//
// DOTPROD4 semantics:
//   acc += sext8(rs1[7:0])  * sext8(rs2[7:0])
//        + sext8(rs1[15:8]) * sext8(rs2[15:8])
//        + sext8(rs1[23:16])* sext8(rs2[23:16])
//        + sext8(rs1[31:24])* sext8(rs2[31:24])
// ============================================================

module dotprod4 (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        valid,      // instruction is dotprod4 custom-0
    input  wire [6:0]  funct7,     // operation select
    input  wire [31:0] rs1_data,   // packed 4× INT8
    input  wire [31:0] rs2_data,   // packed 4× INT8

    output wire        ready,      // result available
    output wire [31:0] result      // accumulator value (for ACC_READ)
);

    // Internal accumulator
    reg signed [31:0] acc;

    // Unpack INT8 values (sign-extend)
    wire signed [7:0] a0 = rs1_data[ 7: 0];
    wire signed [7:0] a1 = rs1_data[15: 8];
    wire signed [7:0] a2 = rs1_data[23:16];
    wire signed [7:0] a3 = rs1_data[31:24];

    wire signed [7:0] b0 = rs2_data[ 7: 0];
    wire signed [7:0] b1 = rs2_data[15: 8];
    wire signed [7:0] b2 = rs2_data[23:16];
    wire signed [7:0] b3 = rs2_data[31:24];

    // Multiply and sum
    wire signed [31:0] dot_sum = (a0 * b0) + (a1 * b1) + (a2 * b2) + (a3 * b3);

    // Operation select
    localparam DOTPROD  = 7'h00;
    localparam ACC_RST  = 7'h01;
    localparam ACC_READ = 7'h02;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc <= 32'h0;
        end else if (valid) begin
            case (funct7)
                DOTPROD: acc <= acc + dot_sum;
                ACC_RST: acc <= 32'h0;
                // ACC_READ: no state change, just output
                default: ;
            endcase
        end
    end

    // Output
    assign result = acc;
    assign ready  = valid;  // single-cycle for all operations

endmodule
