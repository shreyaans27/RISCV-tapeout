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

// ============================================================
// bus_xbar.v — Simple 2-master 2-slave bus crossbar
//
// Address decode:
//   0x08000000-0x08001FFF → Slave 0 (SRAM)
//   0x20000000-0x20003FFF → Slave 1 (ROM)
//   All other addresses   → error (no response)
//
// Arbitration: Master 0 (core) has priority over Master 1 (JTAG)
// Only one transaction at a time per slave.
// ============================================================

module bus_xbar (
    input  wire        clk,
    input  wire        rst_n,

    // Master 0 (Core)
    input  wire        m0_req_valid,
    output wire        m0_req_ready,
    input  wire [31:0] m0_req_addr,
    input  wire [31:0] m0_req_wdata,
    input  wire [3:0]  m0_req_wmask,
    input  wire        m0_req_wen,
    output wire        m0_resp_valid,
    output wire [31:0] m0_resp_rdata,

    // Master 1 (JTAG)
    input  wire        m1_req_valid,
    output wire        m1_req_ready,
    input  wire [31:0] m1_req_addr,
    input  wire [31:0] m1_req_wdata,
    input  wire [3:0]  m1_req_wmask,
    input  wire        m1_req_wen,
    output wire        m1_resp_valid,
    output wire [31:0] m1_resp_rdata,

    // Slave 0 (SRAM)
    output wire        s0_req_valid,
    input  wire        s0_req_ready,
    output wire [31:0] s0_req_addr,
    output wire [31:0] s0_req_wdata,
    output wire [3:0]  s0_req_wmask,
    output wire        s0_req_wen,
    input  wire        s0_resp_valid,
    input  wire [31:0] s0_resp_rdata,

    // Slave 1 (ROM)
    output wire        s1_req_valid,
    input  wire        s1_req_ready,
    output wire [31:0] s1_req_addr,
    output wire [31:0] s1_req_wdata,
    output wire [3:0]  s1_req_wmask,
    output wire        s1_req_wen,
    input  wire        s1_resp_valid,
    input  wire [31:0] s1_resp_rdata
);

    // --------------------------------------------------------
    // Address decode — which slave does each master want?
    // --------------------------------------------------------
    wire m0_sel_sram = (m0_req_addr[31:16] == 16'h0800);
    wire m0_sel_rom  = (m0_req_addr[31:16] == 16'h2000);
    wire m1_sel_sram = (m1_req_addr[31:16] == 16'h0800);
    wire m1_sel_rom  = (m1_req_addr[31:16] == 16'h2000);

    // --------------------------------------------------------
    // Arbitration state — track who owns each slave
    // States: IDLE, M0_ACTIVE, M1_ACTIVE
    // --------------------------------------------------------
    localparam IDLE      = 2'd0;
    localparam M0_ACTIVE = 2'd1;
    localparam M1_ACTIVE = 2'd2;

    reg [1:0] s0_owner, s0_owner_next;
    reg [1:0] s1_owner, s1_owner_next;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s0_owner <= IDLE;
            s1_owner <= IDLE;
        end else begin
            s0_owner <= s0_owner_next;
            s1_owner <= s1_owner_next;
        end
    end

    // --------------------------------------------------------
    // SRAM (S0) arbitration — core has priority
    // --------------------------------------------------------
    wire m0_wants_s0 = m0_req_valid && m0_sel_sram;
    wire m1_wants_s0 = m1_req_valid && m1_sel_sram;

    always @(*) begin
        s0_owner_next = s0_owner;
        case (s0_owner)
            IDLE: begin
                if (m0_wants_s0)
                    s0_owner_next = M0_ACTIVE;
                else if (m1_wants_s0)
                    s0_owner_next = M1_ACTIVE;
            end
            M0_ACTIVE: begin
                if (s0_resp_valid)
                    s0_owner_next = IDLE;
            end
            M1_ACTIVE: begin
                if (s0_resp_valid)
                    s0_owner_next = IDLE;
            end
            default: s0_owner_next = IDLE;
        endcase
    end

    // --------------------------------------------------------
    // ROM (S1) arbitration — core has priority
    // --------------------------------------------------------
    wire m0_wants_s1 = m0_req_valid && m0_sel_rom;
    wire m1_wants_s1 = m1_req_valid && m1_sel_rom;

    always @(*) begin
        s1_owner_next = s1_owner;
        case (s1_owner)
            IDLE: begin
                if (m0_wants_s1)
                    s1_owner_next = M0_ACTIVE;
                else if (m1_wants_s1)
                    s1_owner_next = M1_ACTIVE;
            end
            M0_ACTIVE: begin
                if (s1_resp_valid)
                    s1_owner_next = IDLE;
            end
            M1_ACTIVE: begin
                if (s1_resp_valid)
                    s1_owner_next = IDLE;
            end
            default: s1_owner_next = IDLE;
        endcase
    end

    // --------------------------------------------------------
    // SRAM (S0) mux — connect winning master to slave
    // --------------------------------------------------------
    wire s0_m0_grant = (s0_owner == M0_ACTIVE) || (s0_owner == IDLE && m0_wants_s0);
    wire s0_m1_grant = (s0_owner == M1_ACTIVE) || (s0_owner == IDLE && !m0_wants_s0 && m1_wants_s0);

    assign s0_req_valid = s0_m0_grant ? m0_req_valid && m0_sel_sram :
                          s0_m1_grant ? m1_req_valid && m1_sel_sram : 1'b0;
    assign s0_req_addr  = s0_m0_grant ? m0_req_addr  : m1_req_addr;
    assign s0_req_wdata = s0_m0_grant ? m0_req_wdata : m1_req_wdata;
    assign s0_req_wmask = s0_m0_grant ? m0_req_wmask : m1_req_wmask;
    assign s0_req_wen   = s0_m0_grant ? m0_req_wen   : m1_req_wen;

    // --------------------------------------------------------
    // ROM (S1) mux — connect winning master to slave
    // --------------------------------------------------------
    wire s1_m0_grant = (s1_owner == M0_ACTIVE) || (s1_owner == IDLE && m0_wants_s1);
    wire s1_m1_grant = (s1_owner == M1_ACTIVE) || (s1_owner == IDLE && !m0_wants_s1 && m1_wants_s1);

    assign s1_req_valid = s1_m0_grant ? m0_req_valid && m0_sel_rom :
                          s1_m1_grant ? m1_req_valid && m1_sel_rom : 1'b0;
    assign s1_req_addr  = s1_m0_grant ? m0_req_addr  : m1_req_addr;
    assign s1_req_wdata = s1_m0_grant ? m0_req_wdata : m1_req_wdata;
    assign s1_req_wmask = s1_m0_grant ? m0_req_wmask : m1_req_wmask;
    assign s1_req_wen   = s1_m0_grant ? m0_req_wen   : m1_req_wen;

    // --------------------------------------------------------
    // Response routing — slave responses back to masters
    // --------------------------------------------------------
    assign m0_resp_valid = (s0_m0_grant && s0_resp_valid) ||
                           (s1_m0_grant && s1_resp_valid);
    assign m0_resp_rdata = (s0_m0_grant && s0_resp_valid) ? s0_resp_rdata :
                           (s1_m0_grant && s1_resp_valid) ? s1_resp_rdata : 32'h0;

    assign m1_resp_valid = (s0_m1_grant && s0_resp_valid) ||
                           (s1_m1_grant && s1_resp_valid);
    assign m1_resp_rdata = (s0_m1_grant && s0_resp_valid) ? s0_resp_rdata :
                           (s1_m1_grant && s1_resp_valid) ? s1_resp_rdata : 32'h0;

    // --------------------------------------------------------
    // Ready signals — master is ready when its target slave is ready
    // --------------------------------------------------------
    assign m0_req_ready = (m0_sel_sram && s0_m0_grant && s0_req_ready) ||
                          (m0_sel_rom  && s1_m0_grant && s1_req_ready);

    assign m1_req_ready = (m1_sel_sram && s0_m1_grant && s0_req_ready) ||
                          (m1_sel_rom  && s1_m1_grant && s1_req_ready);

endmodule

// ============================================================
// clk_div.v — 3-stage divide-by-2 frequency divider
//
// Input:  clk_200  (200 MHz from pad)
// Output: clk_100  (100 MHz — for memory controller timing)
//         clk_50   (50 MHz  — core clock)
// ============================================================

module clk_div (
    input  wire clk_200,
    input  wire rst_n,
    output wire clk_100,
    output wire clk_50
);

    // Stage 1: 200 → 100 MHz
    reg div2_reg;
    always @(posedge clk_200 or negedge rst_n) begin
        if (!rst_n)
            div2_reg <= 1'b0;
        else
            div2_reg <= ~div2_reg;
    end
    assign clk_100 = div2_reg;

    // Stage 2: 100 → 50 MHz
    reg div4_reg;
    always @(posedge clk_100 or negedge rst_n) begin
        if (!rst_n)
            div4_reg <= 1'b0;
        else
            div4_reg <= ~div4_reg;
    end
    assign clk_50 = div4_reg;

endmodule

// ============================================================
// sram_ctrl.v — SRAM Controller with macro timing
//
// Timing (one clk_50 period = 20ns):
//   posedge clk_50 (0ns):    ADDR, DIN, WEN stable
//                             PRECHG=LOW, DEN=LOW, EN=LOW, REN=LOW
//   negedge clk_50 (10ns):   PRECHG=HIGH, DEN=HIGH, EN=HIGH
//   negedge clk_200 (12.5ns): REN=HIGH (2.5ns delay after DEN)
//   posedge clk_50 (20ns):   DOUT valid, latch into resp_rdata
//
// Only supports word-aligned 32-bit writes (no SB/SH).
// ============================================================

module sram_ctrl (
    input  wire        clk,         // clk_50
    input  wire        clk_fast,    // clk_200 (for REN timing)
    input  wire        rst_n,

    // Bus interface
    input  wire        req_valid,
    output reg         req_ready,
    input  wire [31:0] req_addr,
    input  wire [31:0] req_wdata,
    input  wire [3:0]  req_wmask,
    input  wire        req_wen,
    output reg         resp_valid,
    output reg  [31:0] resp_rdata,

    // SRAM macro pins
    output reg         sram_den,
    output reg  [7:0]  sram_addr,
    output reg  [2:0]  sram_col_addr,
    output reg         sram_prechg,
    output reg         sram_ren,
    output reg         sram_wen,
    output reg         sram_en,
    output reg  [31:0] sram_din,
    input  wire [31:0] sram_dout
);

    wire [7:0] row_addr = req_addr[12:5];
    wire [2:0] col_addr = req_addr[4:2];

    localparam IDLE    = 2'd0;
    localparam ACCESS  = 2'd1;
    localparam RESPOND = 2'd2;

    reg [1:0] state;

    // --------------------------------------------------------
    // Posedge clk_50: bus handshake + stable SRAM pins + latch DOUT
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            req_ready     <= 1'b1;
            resp_valid    <= 1'b0;
            resp_rdata    <= 32'h0;
            sram_addr     <= 8'h0;
            sram_col_addr <= 3'h0;
            sram_din      <= 32'h0;
            sram_wen      <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    resp_valid <= 1'b0;
                    sram_wen   <= 1'b0;

                    if (req_valid && req_ready) begin
                        sram_addr     <= row_addr;
                        sram_col_addr <= col_addr;
                        sram_din      <= req_wdata;
                        sram_wen      <= req_wen;

                        req_ready <= 1'b0;
                        state     <= ACCESS;
                    end
                end

                ACCESS: begin
                    resp_rdata <= sram_dout;
                    resp_valid <= 1'b1;
                    sram_wen   <= 1'b0;
                    state      <= RESPOND;
                end

                RESPOND: begin
                    resp_valid <= 1'b0;
                    req_ready  <= 1'b1;
                    state      <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // --------------------------------------------------------
    // Negedge clk_50: PRECHG, DEN, EN transitions
    //   ACCESS: PRECHG=HIGH, DEN=HIGH, EN=HIGH (precharge done)
    //   else:   PRECHG=LOW, DEN=LOW, EN=LOW (precharging)
    // --------------------------------------------------------
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sram_prechg <= 1'b0;
            sram_den    <= 1'b0;
            sram_en     <= 1'b0;
        end else begin
            if (state == ACCESS) begin
                sram_prechg <= 1'b1;
                sram_den    <= 1'b1;
                sram_en     <= 1'b1;
            end else begin
                sram_prechg <= 1'b0;
                sram_den    <= 1'b0;
                sram_en     <= 1'b0;
            end
        end
    end

    // --------------------------------------------------------
    // Negedge clk_200: REN transition (2.5ns after DEN)
    //   Assert REN when DEN is already high (set by negedge clk_50)
    //   negedge clk_200 at 12.5ns is 2.5ns after negedge clk_50 at 10ns
    // --------------------------------------------------------
    always @(negedge clk_fast or negedge rst_n) begin
        if (!rst_n) begin
            sram_ren <= 1'b0;
        end else begin
            if (state == ACCESS && sram_den) begin
                sram_ren <= 1'b1;
            end else begin
                sram_ren <= 1'b0;
            end
        end
    end

endmodule

// ============================================================
// rom_ctrl.v — ROM Controller with macro timing
//
// ROM Macro Pins:
//   rom_wl_addr<7:0>  — word line address
//   rom_col_in<3:0>   — column mux input
//   rom_preen         — precharge enable (active high = precharging)
//   rom_wlen          — word line enable (active high)
//   rom_saen          — sense amp enable (active high)
//   rom_dout<31:0>    — data out
//
// Timing (one clk_50 period = 20ns):
//   posedge clk_50 (0ns):   ADDR/COL stable, PREEN=HIGH, WLEN=LOW, SAEN=LOW
//   negedge clk_50 (10ns):  PREEN=LOW, WLEN=HIGH
//   posedge clk_200 (15ns): SAEN=HIGH (5ns after WLEN)
//   next posedge clk_50 (20ns): DOUT valid, latch
// ============================================================

module rom_ctrl (
    input  wire        clk,         // clk_50
    input  wire        clk_fast,    // clk_200 for SAEN timing
    input  wire        rst_n,

    // Bus interface
    input  wire        req_valid,
    output reg         req_ready,
    input  wire [31:0] req_addr,
    output reg         resp_valid,
    output reg  [31:0] resp_rdata,

    // ROM macro pins
    output reg  [7:0]  rom_wl_addr,
    output reg  [3:0]  rom_col_in,
    output reg         rom_preen,
    output reg         rom_wlen,
    output reg         rom_saen,
    input  wire [31:0] rom_dout
);

    wire [7:0] wl_addr  = req_addr[9:2];
    wire [3:0] col_addr = req_addr[13:10];

    localparam IDLE    = 2'd0;
    localparam ACCESS  = 2'd1;
    localparam RESPOND = 2'd2;

    reg [1:0] state;

    // --------------------------------------------------------
    // Posedge clk_50: bus handshake + stable pins + latch DOUT
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            req_ready    <= 1'b1;
            resp_valid   <= 1'b0;
            resp_rdata   <= 32'h0;
            rom_wl_addr  <= 8'h0;
            rom_col_in   <= 4'h0;
        end else begin
            case (state)
                IDLE: begin
                    resp_valid <= 1'b0;

                    if (req_valid && req_ready) begin
                        rom_wl_addr <= wl_addr;
                        rom_col_in  <= col_addr;
                        req_ready   <= 1'b0;
                        state       <= ACCESS;
                    end
                end

                ACCESS: begin
                    // DOUT valid now (negedge set WLEN, clk_200 set SAEN)
                    resp_rdata <= rom_dout;
                    resp_valid <= 1'b1;
                    state      <= RESPOND;
                end

                RESPOND: begin
                    resp_valid <= 1'b0;
                    req_ready  <= 1'b1;
                    state      <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

    // --------------------------------------------------------
    // Negedge clk_50: PREEN and WLEN transitions
    // --------------------------------------------------------
    always @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rom_preen <= 1'b1;   // precharging during reset
            rom_wlen  <= 1'b0;
        end else begin
            if (state == ACCESS) begin
                rom_preen <= 1'b0;   // precharge done
                rom_wlen  <= 1'b1;   // word line active
            end else begin
                rom_preen <= 1'b1;   // precharging
                rom_wlen  <= 1'b0;
            end
        end
    end

    // --------------------------------------------------------
    // Posedge clk_200: SAEN transition (5ns after negedge clk_50)
    // Only assert when WLEN is already high (set by negedge)
    // --------------------------------------------------------
    always @(posedge clk_fast or negedge rst_n) begin
        if (!rst_n) begin
            rom_saen <= 1'b0;
        end else begin
            if (state == ACCESS && rom_wlen) begin
                rom_saen <= 1'b1;
            end else begin
                rom_saen <= 1'b0;
            end
        end
    end

endmodule

// ============================================================
// jtag_bridge.v — Minimal JTAG-to-bus bridge (STUB)
//
// For simulation: core_rst_n directly follows rst_n
// No JTAG activity — core runs immediately after reset.
// Full JTAG TAP implementation added later for tapeout.
// ============================================================

module jtag_bridge (
    input  wire        clk,
    input  wire        rst_n,

    // JTAG pins
    input  wire        jtag_tck,
    input  wire        jtag_tms,
    input  wire        jtag_tdi,
    output wire        jtag_tdo,

    // Core reset control
    output wire        core_rst_n,

    // Bus master interface (inactive for now)
    output wire        req_valid,
    input  wire        req_ready,
    output wire [31:0] req_addr,
    output wire [31:0] req_wdata,
    output wire [3:0]  req_wmask,
    output wire        req_wen,
    input  wire        resp_valid,
    input  wire [31:0] resp_rdata
);

    // Stub: core reset follows system reset
    assign core_rst_n = rst_n;

    // Stub: no bus activity
    assign req_valid = 1'b0;
    assign req_addr  = 32'h0;
    assign req_wdata = 32'h0;
    assign req_wmask = 4'h0;
    assign req_wen   = 1'b0;

    // JTAG TDO — idle
    assign jtag_tdo = 1'b0;

endmodule

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

// ============================================================
// core_top.v — Minimal ML Inference SoC Top Level
//
// Clocking:
//   pad_clk (200MHz) → clk_div → clk_100 (mem ctrl) + clk_50 (core)
//
// Memory Map:
//   0x08000000 - 0x08001FFF : 8KB SRAM
//   0x20000000 - 0x20003FFF : 16KB ROM
//
// SRAM and ROM macros are EXTERNAL — not in this RTL.
// Controllers output raw control signals to top-level ports.
// These get manually routed to macro pads during P&R.
// ============================================================

module core_top (
    input  wire        pad_clk,     // 200 MHz pad clock
    input  wire        rst_n,       // active-low reset

    // JTAG interface
    input  wire        jtag_tck,
    input  wire        jtag_tms,
    input  wire        jtag_tdi,
    output wire        jtag_tdo,

    // SRAM macro pins (directly to pads)
    output wire        sram_den,        // decoder enable (active high)
    output wire [7:0]  sram_addr,       // row address A<7:0>
    output wire [2:0]  sram_col_addr,   // column mux address C<2:0>
    output wire        sram_prechg,     // precharge (active low)
    output wire        sram_ren,        // read/sense enable
    output wire        sram_wen,        // write enable
    output wire        sram_en,         // column mux enable
    output wire [31:0] sram_din,        // data in
    input  wire [31:0] sram_dout,       // data out

    // ROM macro pins (directly to pads)
    output wire [7:0]  rom_wl_addr,
    output wire [3:0]  rom_col_in,
    output wire        rom_preen,
    output wire        rom_wlen,
    output wire        rom_saen,
    input  wire [31:0] rom_dout,

    // Debug outputs (anchor pipeline for synthesis)
    output wire [31:0] debug_pc,
    output wire        debug_resp_valid
);

    // --------------------------------------------------------
    // Clock generation
    // --------------------------------------------------------
    wire clk_100;
    wire clk_50;

    clk_div u_clk_div (
        .clk_200 (pad_clk),
        .rst_n   (rst_n),
        .clk_100 (clk_100),
        .clk_50  (clk_50)
    );

    // --------------------------------------------------------
    // Core bus master signals
    // --------------------------------------------------------
    wire        core_req_valid;
    wire        core_req_ready;
    wire [31:0] core_req_addr;
    wire [31:0] core_req_wdata;
    wire [3:0]  core_req_wmask;
    wire        core_req_wen;
    wire        core_resp_valid;
    wire [31:0] core_resp_rdata;

    // --------------------------------------------------------
    // JTAG bus master signals
    // --------------------------------------------------------
    wire        jtag_req_valid;
    wire        jtag_req_ready;
    wire [31:0] jtag_req_addr;
    wire [31:0] jtag_req_wdata;
    wire [3:0]  jtag_req_wmask;
    wire        jtag_req_wen;
    wire        jtag_resp_valid;
    wire [31:0] jtag_resp_rdata;

    // --------------------------------------------------------
    // SRAM slave bus signals
    // --------------------------------------------------------
    wire        sram_bus_req_valid;
    wire        sram_bus_req_ready;
    wire [31:0] sram_bus_req_addr;
    wire [31:0] sram_bus_req_wdata;
    wire [3:0]  sram_bus_req_wmask;
    wire        sram_bus_req_wen;
    wire        sram_bus_resp_valid;
    wire [31:0] sram_bus_resp_rdata;

    // --------------------------------------------------------
    // ROM slave bus signals
    // --------------------------------------------------------
    wire        rom_bus_req_valid;
    wire        rom_bus_req_ready;
    wire [31:0] rom_bus_req_addr;
    wire        rom_bus_req_wen;
    wire        rom_bus_resp_valid;
    wire [31:0] rom_bus_resp_rdata;

    // --------------------------------------------------------
    // Core reset (controlled by JTAG bridge)
    // --------------------------------------------------------
    wire core_rst_n;

    // --------------------------------------------------------
    // Debug outputs
    // --------------------------------------------------------
    assign debug_pc         = core_req_addr;
    assign debug_resp_valid = core_resp_valid;

    // --------------------------------------------------------
    // RV32IM Core (clk_50)
    // --------------------------------------------------------
    rv32im_core u_core (
        .clk            (clk_50),
        .rst_n          (core_rst_n),
        .req_valid      (core_req_valid),
        .req_ready      (core_req_ready),
        .req_addr       (core_req_addr),
        .req_wdata      (core_req_wdata),
        .req_wmask      (core_req_wmask),
        .req_wen        (core_req_wen),
        .resp_valid     (core_resp_valid),
        .resp_rdata     (core_resp_rdata)
    );

    // --------------------------------------------------------
    // JTAG Bridge (clk_50)
    // --------------------------------------------------------
    jtag_bridge u_jtag (
        .clk            (clk_50),
        .rst_n          (rst_n),
        .jtag_tck       (jtag_tck),
        .jtag_tms       (jtag_tms),
        .jtag_tdi       (jtag_tdi),
        .jtag_tdo       (jtag_tdo),
        .core_rst_n     (core_rst_n),
        .req_valid      (jtag_req_valid),
        .req_ready      (jtag_req_ready),
        .req_addr       (jtag_req_addr),
        .req_wdata      (jtag_req_wdata),
        .req_wmask      (jtag_req_wmask),
        .req_wen        (jtag_req_wen),
        .resp_valid     (jtag_resp_valid),
        .resp_rdata     (jtag_resp_rdata)
    );

    // --------------------------------------------------------
    // Bus Crossbar (clk_50)
    // --------------------------------------------------------
    bus_xbar u_xbar (
        .clk            (clk_50),
        .rst_n          (rst_n),
        .m0_req_valid   (core_req_valid),
        .m0_req_ready   (core_req_ready),
        .m0_req_addr    (core_req_addr),
        .m0_req_wdata   (core_req_wdata),
        .m0_req_wmask   (core_req_wmask),
        .m0_req_wen     (core_req_wen),
        .m0_resp_valid  (core_resp_valid),
        .m0_resp_rdata  (core_resp_rdata),
        .m1_req_valid   (jtag_req_valid),
        .m1_req_ready   (jtag_req_ready),
        .m1_req_addr    (jtag_req_addr),
        .m1_req_wdata   (jtag_req_wdata),
        .m1_req_wmask   (jtag_req_wmask),
        .m1_req_wen     (jtag_req_wen),
        .m1_resp_valid  (jtag_resp_valid),
        .m1_resp_rdata  (jtag_resp_rdata),
        .s0_req_valid   (sram_bus_req_valid),
        .s0_req_ready   (sram_bus_req_ready),
        .s0_req_addr    (sram_bus_req_addr),
        .s0_req_wdata   (sram_bus_req_wdata),
        .s0_req_wmask   (sram_bus_req_wmask),
        .s0_req_wen     (sram_bus_req_wen),
        .s0_resp_valid  (sram_bus_resp_valid),
        .s0_resp_rdata  (sram_bus_resp_rdata),
        .s1_req_valid   (rom_bus_req_valid),
        .s1_req_ready   (rom_bus_req_ready),
        .s1_req_addr    (rom_bus_req_addr),
        .s1_req_wdata   (),             // ROM is read-only
        .s1_req_wmask   (),
        .s1_req_wen     (rom_bus_req_wen),
        .s1_resp_valid  (rom_bus_resp_valid),
        .s1_resp_rdata  (rom_bus_resp_rdata)
    );

    // --------------------------------------------------------
    // SRAM Controller (clk_50 bus + clk_200 timing)
    // --------------------------------------------------------
    sram_ctrl u_sram (
        .clk            (clk_50),
        .clk_fast       (pad_clk),
        .rst_n          (rst_n),
        // Bus side
        .req_valid      (sram_bus_req_valid),
        .req_ready      (sram_bus_req_ready),
        .req_addr       (sram_bus_req_addr),
        .req_wdata      (sram_bus_req_wdata),
        .req_wmask      (sram_bus_req_wmask),
        .req_wen        (sram_bus_req_wen),
        .resp_valid     (sram_bus_resp_valid),
        .resp_rdata     (sram_bus_resp_rdata),
        // SRAM macro pins
        .sram_den       (sram_den),
        .sram_addr      (sram_addr),
        .sram_col_addr  (sram_col_addr),
        .sram_prechg    (sram_prechg),
        .sram_ren       (sram_ren),
        .sram_wen       (sram_wen),
        .sram_en        (sram_en),
        .sram_din       (sram_din),
        .sram_dout      (sram_dout)
    );

    // --------------------------------------------------------
    // ROM Controller (clk_50 bus + clk_200 timing)
    // --------------------------------------------------------
    rom_ctrl u_rom (
        .clk            (clk_50),
        .clk_fast       (pad_clk),
        .rst_n          (rst_n),
        // Bus side
        .req_valid      (rom_bus_req_valid),
        .req_ready      (rom_bus_req_ready),
        .req_addr       (rom_bus_req_addr),
        .resp_valid     (rom_bus_resp_valid),
        .resp_rdata     (rom_bus_resp_rdata),
        // ROM macro pins
        .rom_wl_addr    (rom_wl_addr),
        .rom_col_in     (rom_col_in),
        .rom_preen      (rom_preen),
        .rom_wlen       (rom_wlen),
        .rom_saen       (rom_saen),
        .rom_dout       (rom_dout)
    );

endmodule

