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
