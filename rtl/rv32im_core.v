// ============================================================
// rv32im_core.v — Minimal RV32IM Core
//
// 3-stage pipeline: Fetch → Decode/Execute → Writeback
// Supports: RV32IM base integer + multiply
// Custom: dotprod4 (opcode 0x0B)
// No: CSRs (except mcycle stub), no interrupts, no VM, no PMP
//
// Memory interface: simple valid/ready bus master
// Reset vector: 0x08000000
// ============================================================

module rv32im_core (
    input  wire        clk,
    input  wire        rst_n,

    // Bus master interface
    output reg         req_valid,
    input  wire        req_ready,
    output reg  [31:0] req_addr,
    output reg  [31:0] req_wdata,
    output reg  [3:0]  req_wmask,
    output reg         req_wen,
    input  wire        resp_valid,
    input  wire [31:0] resp_rdata
);

    // --------------------------------------------------------
    // Constants
    // --------------------------------------------------------
    localparam RESET_VEC = 32'h08000000;

    // Opcodes
    localparam OP_LUI    = 7'b0110111;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_ARITHI = 7'b0010011;
    localparam OP_ARITH  = 7'b0110011;
    localparam OP_FENCE  = 7'b0001111;
    localparam OP_SYSTEM = 7'b1110011;
    localparam OP_CUSTOM0= 7'b0001011;

    // ALU ops
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

    // Pipeline states
    localparam S_FETCH   = 3'd0;
    localparam S_FETCH_W = 3'd1;
    localparam S_EXECUTE = 3'd2;
    localparam S_MEM     = 3'd3;
    localparam S_MEM_W   = 3'd4;

    reg [2:0] state;

    // --------------------------------------------------------
    // PC
    // --------------------------------------------------------
    reg [31:0] pc;

    // --------------------------------------------------------
    // Instruction register
    // --------------------------------------------------------
    reg [31:0] instr;

    wire [6:0]  opcode = instr[6:0];
    wire [4:0]  rd     = instr[11:7];
    wire [2:0]  funct3 = instr[14:12];
    wire [4:0]  rs1    = instr[19:15];
    wire [4:0]  rs2    = instr[24:20];
    wire [6:0]  funct7 = instr[31:25];

    // --------------------------------------------------------
    // Immediate decode
    // --------------------------------------------------------
    wire [31:0] imm_i = {{20{instr[31]}}, instr[31:20]};
    wire [31:0] imm_s = {{20{instr[31]}}, instr[31:25], instr[11:7]};
    wire [31:0] imm_b = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
    wire [31:0] imm_u = {instr[31:12], 12'b0};
    wire [31:0] imm_j = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};

    // --------------------------------------------------------
    // Register file
    // --------------------------------------------------------
    reg         rf_wr_en;
    reg  [4:0]  rf_wr_addr;
    reg  [31:0] rf_wr_data;
    wire [31:0] rs1_data, rs2_data;

    regfile u_rf (
        .clk      (clk),
        .rst_n    (rst_n),
        .rs1_addr (rs1),
        .rs1_data (rs1_data),
        .rs2_addr (rs2),
        .rs2_data (rs2_data),
        .wr_en    (rf_wr_en),
        .wr_addr  (rf_wr_addr),
        .wr_data  (rf_wr_data)
    );

    // --------------------------------------------------------
    // ALU operation decode (combinational)
    // --------------------------------------------------------
    reg [3:0] decoded_alu_op;
    always @(*) begin
        decoded_alu_op = ALU_ADD;
        case (opcode)
            OP_ARITHI: begin
                case (funct3)
                    3'b000: decoded_alu_op = ALU_ADD;
                    3'b010: decoded_alu_op = ALU_SLT;
                    3'b011: decoded_alu_op = ALU_SLTU;
                    3'b100: decoded_alu_op = ALU_XOR;
                    3'b110: decoded_alu_op = ALU_OR;
                    3'b111: decoded_alu_op = ALU_AND;
                    3'b001: decoded_alu_op = ALU_SLL;
                    3'b101: decoded_alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                    default: decoded_alu_op = ALU_ADD;
                endcase
            end
            OP_ARITH: begin
                if (funct7 == 7'h01) begin
                    case (funct3)
                        3'b000: decoded_alu_op = ALU_MUL;
                        3'b001: decoded_alu_op = ALU_MULH;
                        3'b010: decoded_alu_op = ALU_MULHSU;
                        3'b011: decoded_alu_op = ALU_MULHU;
                        default: decoded_alu_op = ALU_ADD;
                    endcase
                end else begin
                    case (funct3)
                        3'b000: decoded_alu_op = funct7[5] ? ALU_SUB : ALU_ADD;
                        3'b001: decoded_alu_op = ALU_SLL;
                        3'b010: decoded_alu_op = ALU_SLT;
                        3'b011: decoded_alu_op = ALU_SLTU;
                        3'b100: decoded_alu_op = ALU_XOR;
                        3'b101: decoded_alu_op = funct7[5] ? ALU_SRA : ALU_SRL;
                        3'b110: decoded_alu_op = ALU_OR;
                        3'b111: decoded_alu_op = ALU_AND;
                        default: decoded_alu_op = ALU_ADD;
                    endcase
                end
            end
            default: decoded_alu_op = ALU_ADD;
        endcase
    end

    // --------------------------------------------------------
    // ALU — combinational inputs from current instruction
    // --------------------------------------------------------
    wire [3:0]  alu_op = decoded_alu_op;
    wire [31:0] alu_a  = (opcode == OP_AUIPC) ? pc : rs1_data;
    wire [31:0] alu_b  = (opcode == OP_ARITH || opcode == OP_BRANCH) ? rs2_data :
                         (opcode == OP_STORE) ? imm_s : imm_i;
    wire [31:0] alu_result;
    wire        alu_zero;

    alu u_alu (
        .op     (alu_op),
        .a      (alu_a),
        .b      (alu_b),
        .result (alu_result),
        .zero   (alu_zero)
    );

    // --------------------------------------------------------
    // DotProd4
    // --------------------------------------------------------
    reg         dp_valid;
    wire        dp_ready;
    wire [31:0] dp_result;

    dotprod4 u_dp (
        .clk      (clk),
        .rst_n    (rst_n),
        .valid    (dp_valid),
        .funct7   (funct7),
        .rs1_data (rs1_data),
        .rs2_data (rs2_data),
        .ready    (dp_ready),
        .result   (dp_result)
    );

    // --------------------------------------------------------
    // Branch comparison (combinational)
    // --------------------------------------------------------
    reg branch_taken;
    always @(*) begin
        case (funct3)
            3'b000: branch_taken = (rs1_data == rs2_data);
            3'b001: branch_taken = (rs1_data != rs2_data);
            3'b100: branch_taken = ($signed(rs1_data) < $signed(rs2_data));
            3'b101: branch_taken = ($signed(rs1_data) >= $signed(rs2_data));
            3'b110: branch_taken = (rs1_data < rs2_data);
            3'b111: branch_taken = (rs1_data >= rs2_data);
            default: branch_taken = 1'b0;
        endcase
    end

    // --------------------------------------------------------
    // Memory access helpers
    // --------------------------------------------------------
    reg [31:0] mem_addr_reg;

    // Load alignment
    reg [31:0] mem_result;
    always @(*) begin
        case (funct3)
            3'b000: begin // LB
                case (mem_addr_reg[1:0])
                    2'b00: mem_result = {{24{resp_rdata[ 7]}}, resp_rdata[ 7: 0]};
                    2'b01: mem_result = {{24{resp_rdata[15]}}, resp_rdata[15: 8]};
                    2'b10: mem_result = {{24{resp_rdata[23]}}, resp_rdata[23:16]};
                    2'b11: mem_result = {{24{resp_rdata[31]}}, resp_rdata[31:24]};
                endcase
            end
            3'b001: begin // LH
                case (mem_addr_reg[1])
                    1'b0: mem_result = {{16{resp_rdata[15]}}, resp_rdata[15: 0]};
                    1'b1: mem_result = {{16{resp_rdata[31]}}, resp_rdata[31:16]};
                endcase
            end
            3'b010: mem_result = resp_rdata; // LW
            3'b100: begin // LBU
                case (mem_addr_reg[1:0])
                    2'b00: mem_result = {24'b0, resp_rdata[ 7: 0]};
                    2'b01: mem_result = {24'b0, resp_rdata[15: 8]};
                    2'b10: mem_result = {24'b0, resp_rdata[23:16]};
                    2'b11: mem_result = {24'b0, resp_rdata[31:24]};
                endcase
            end
            3'b101: begin // LHU
                case (mem_addr_reg[1])
                    1'b0: mem_result = {16'b0, resp_rdata[15: 0]};
                    1'b1: mem_result = {16'b0, resp_rdata[31:16]};
                endcase
            end
            default: mem_result = resp_rdata;
        endcase
    end

    // Store alignment
    reg [31:0] store_data;
    reg [3:0]  store_mask;
    always @(*) begin
        case (funct3)
            3'b000: begin // SB
                case (mem_addr_reg[1:0])
                    2'b00: begin store_data = {24'b0, rs2_data[7:0]};       store_mask = 4'b0001; end
                    2'b01: begin store_data = {16'b0, rs2_data[7:0], 8'b0}; store_mask = 4'b0010; end
                    2'b10: begin store_data = {8'b0, rs2_data[7:0], 16'b0}; store_mask = 4'b0100; end
                    2'b11: begin store_data = {rs2_data[7:0], 24'b0};       store_mask = 4'b1000; end
                endcase
            end
            3'b001: begin // SH
                case (mem_addr_reg[1])
                    1'b0: begin store_data = {16'b0, rs2_data[15:0]};       store_mask = 4'b0011; end
                    1'b1: begin store_data = {rs2_data[15:0], 16'b0};       store_mask = 4'b1100; end
                endcase
            end
            3'b010: begin // SW
                store_data = rs2_data;
                store_mask = 4'b1111;
            end
            default: begin
                store_data = rs2_data;
                store_mask = 4'b1111;
            end
        endcase
    end

    // --------------------------------------------------------
    // mcycle counter
    // --------------------------------------------------------
    reg [31:0] mcycle;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mcycle <= 32'h0;
        else
            mcycle <= mcycle + 1;
    end

    // --------------------------------------------------------
    // Main state machine
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_FETCH;
            pc         <= RESET_VEC;
            instr      <= 32'h00000013; // NOP
            req_valid  <= 1'b0;
            req_addr   <= 32'h0;
            req_wdata  <= 32'h0;
            req_wmask  <= 4'h0;
            req_wen    <= 1'b0;
            rf_wr_en   <= 1'b0;
            rf_wr_addr <= 5'h0;
            rf_wr_data <= 32'h0;
            dp_valid   <= 1'b0;
            mem_addr_reg <= 32'h0;
        end else begin
            // Defaults
            rf_wr_en <= 1'b0;
            dp_valid <= 1'b0;

            case (state)
                // ============================================
                // FETCH
                // ============================================
                S_FETCH: begin
                    req_valid <= 1'b1;
                    req_addr  <= pc;
                    req_wen   <= 1'b0;
                    req_wmask <= 4'b0000;
                    state     <= S_FETCH_W;
                end

                // ============================================
                // FETCH_WAIT
                // ============================================
                S_FETCH_W: begin
                    if (resp_valid) begin
                        req_valid <= 1'b0;
                        instr     <= resp_rdata;
                        state     <= S_EXECUTE;
                    end
                end

                // ============================================
                // EXECUTE
                // ============================================
                S_EXECUTE: begin
                    case (opcode)
                        OP_LUI: begin
                            rf_wr_en   <= 1'b1;
                            rf_wr_addr <= rd;
                            rf_wr_data <= imm_u;
                            pc         <= pc + 4;
                            state      <= S_FETCH;
                        end

                        OP_AUIPC: begin
                            rf_wr_en   <= 1'b1;
                            rf_wr_addr <= rd;
                            rf_wr_data <= alu_result; // pc + imm_u
                            pc         <= pc + 4;
                            state      <= S_FETCH;
                        end

                        OP_JAL: begin
                            rf_wr_en   <= 1'b1;
                            rf_wr_addr <= rd;
                            rf_wr_data <= pc + 4;
                            pc         <= pc + imm_j;
                            state      <= S_FETCH;
                        end

                        OP_JALR: begin
                            rf_wr_en   <= 1'b1;
                            rf_wr_addr <= rd;
                            rf_wr_data <= pc + 4;
                            pc         <= (rs1_data + imm_i) & 32'hFFFFFFFE;
                            state      <= S_FETCH;
                        end

                        OP_BRANCH: begin
                            if (branch_taken)
                                pc <= pc + imm_b;
                            else
                                pc <= pc + 4;
                            state <= S_FETCH;
                        end

                        OP_LOAD: begin
                            mem_addr_reg <= alu_result; // rs1 + imm_i
                            state        <= S_MEM;
                        end

                        OP_STORE: begin
                            mem_addr_reg <= alu_result; // rs1 + imm_s
                            state        <= S_MEM;
                        end

                        OP_ARITHI: begin
                            rf_wr_en   <= 1'b1;
                            rf_wr_addr <= rd;
                            rf_wr_data <= alu_result;
                            pc         <= pc + 4;
                            state      <= S_FETCH;
                        end

                        OP_ARITH: begin
                            rf_wr_en   <= 1'b1;
                            rf_wr_addr <= rd;
                            rf_wr_data <= alu_result;
                            pc         <= pc + 4;
                            state      <= S_FETCH;
                        end

                        OP_FENCE: begin
                            pc    <= pc + 4;
                            state <= S_FETCH;
                        end

                        OP_SYSTEM: begin
                            if (funct3 != 3'b000) begin
                                rf_wr_en   <= 1'b1;
                                rf_wr_addr <= rd;
                                rf_wr_data <= mcycle;
                            end
                            pc    <= pc + 4;
                            state <= S_FETCH;
                        end

                        OP_CUSTOM0: begin
                            dp_valid <= 1'b1;
                            if (funct7 == 7'h02) begin
                                rf_wr_en   <= 1'b1;
                                rf_wr_addr <= rd;
                                rf_wr_data <= dp_result;
                            end
                            pc    <= pc + 4;
                            state <= S_FETCH;
                        end

                        default: begin
                            pc    <= pc + 4;
                            state <= S_FETCH;
                        end
                    endcase
                end

                // ============================================
                // MEM — issue load/store request
                // ============================================
                S_MEM: begin
                    req_valid <= 1'b1;
                    req_addr  <= {mem_addr_reg[31:2], 2'b00};
                    if (opcode == OP_STORE) begin
                        req_wen   <= 1'b1;
                        req_wdata <= store_data;
                        req_wmask <= store_mask;
                    end else begin
                        req_wen   <= 1'b0;
                        req_wmask <= 4'b0000;
                    end
                    state <= S_MEM_W;
                end

                // ============================================
                // MEM_WAIT
                // ============================================
                S_MEM_W: begin
                    if (resp_valid) begin
                        req_valid <= 1'b0;
                        if (opcode == OP_LOAD) begin
                            rf_wr_en   <= 1'b1;
                            rf_wr_addr <= rd;
                            rf_wr_data <= mem_result;
                        end
                        pc    <= pc + 4;
                        state <= S_FETCH;
                    end
                end

                default: state <= S_FETCH;
            endcase
        end
    end

endmodule
