// ============================================================
// alu.v — RV32IM ALU
//
// Two separate outputs to break multiplier from critical path:
//   result_fast — add/sub/logic/shift/slt ONLY (no multiplier)
//   mul_result  — raw 64-bit multiplier output (goes to pipeline reg)
// ============================================================

module alu (
    input  wire [3:0]  op,
    input  wire [31:0] a,
    input  wire [31:0] b,
    output reg  [31:0] result_fast,   // fast path: no multiplier
    output wire [63:0] mul_result_ss, // signed × signed
    output wire [63:0] mul_result_su, // signed × unsigned
    output wire [63:0] mul_result_uu, // unsigned × unsigned
    output wire        zero
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

    wire [4:0] shamt = b[4:0];

    // Multiplier — completely isolated, not in result_fast cone
    wire signed [31:0] a_signed = a;
    wire signed [31:0] b_signed = b;
    assign mul_result_ss = a_signed * b_signed;
    assign mul_result_su = a_signed * {1'b0, b};
    assign mul_result_uu = {1'b0, a} * {1'b0, b};

    // Fast result — add/sub/logic/shift/slt ONLY
    always @(*) begin
        case (op)
            ALU_ADD:    result_fast = a + b;
            ALU_SUB:    result_fast = a - b;
            ALU_AND:    result_fast = a & b;
            ALU_OR:     result_fast = a | b;
            ALU_XOR:    result_fast = a ^ b;
            ALU_SLL:    result_fast = a << shamt;
            ALU_SRL:    result_fast = a >> shamt;
            ALU_SRA:    result_fast = $signed(a) >>> shamt;
            ALU_SLT:    result_fast = {31'b0, ($signed(a) < $signed(b))};
            ALU_SLTU:   result_fast = {31'b0, (a < b)};
            default:    result_fast = 32'h0;
        endcase
    end

    assign zero = (result_fast == 32'h0);

endmodule
