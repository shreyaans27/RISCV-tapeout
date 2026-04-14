// ============================================================
// alu.v — RV32IM ALU
//
// Supports: add, sub, and, or, xor, sll, srl, sra, slt, sltu
// Branch comparisons: eq, ne, lt, ge, ltu, geu
// Multiply: mul, mulh, mulhsu, mulhu (single-cycle)
// ============================================================

module alu (
    input  wire [3:0]  op,         // ALU operation select
    input  wire [31:0] a,          // operand A (rs1 or PC)
    input  wire [31:0] b,          // operand B (rs2 or immediate)
    output reg  [31:0] result,     // ALU result
    output wire        zero        // result == 0
);

    // ALU operation encoding
    localparam ALU_ADD  = 4'd0;
    localparam ALU_SUB  = 4'd1;
    localparam ALU_AND  = 4'd2;
    localparam ALU_OR   = 4'd3;
    localparam ALU_XOR  = 4'd4;
    localparam ALU_SLL  = 4'd5;
    localparam ALU_SRL  = 4'd6;
    localparam ALU_SRA  = 4'd7;
    localparam ALU_SLT  = 4'd8;
    localparam ALU_SLTU = 4'd9;
    localparam ALU_MUL  = 4'd10;
    localparam ALU_MULH = 4'd11;
    localparam ALU_MULHSU = 4'd12;
    localparam ALU_MULHU  = 4'd13;

    // Sign-extended shift amount
    wire [4:0] shamt = b[4:0];

    // Multiply — 32×32 → 64
    wire signed [31:0] a_signed = a;
    wire signed [31:0] b_signed = b;
    wire signed [63:0] mul_ss = a_signed * b_signed;           // mulh
    wire signed [63:0] mul_su = a_signed * {1'b0, b};          // mulhsu
    wire        [63:0] mul_uu = {1'b0, a} * {1'b0, b};        // mulhu, mul

    always @(*) begin
        case (op)
            ALU_ADD:    result = a + b;
            ALU_SUB:    result = a - b;
            ALU_AND:    result = a & b;
            ALU_OR:     result = a | b;
            ALU_XOR:    result = a ^ b;
            ALU_SLL:    result = a << shamt;
            ALU_SRL:    result = a >> shamt;
            ALU_SRA:    result = $signed(a) >>> shamt;
            ALU_SLT:    result = {31'b0, ($signed(a) < $signed(b))};
            ALU_SLTU:   result = {31'b0, (a < b)};
            ALU_MUL:    result = mul_uu[31:0];
            ALU_MULH:   result = mul_ss[63:32];
            ALU_MULHSU: result = mul_su[63:32];
            ALU_MULHU:  result = mul_uu[63:32];
            default:    result = 32'h0;
        endcase
    end

    assign zero = (result == 32'h0);

endmodule
