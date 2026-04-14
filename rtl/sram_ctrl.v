// ============================================================
// sram_ctrl.v — SRAM Controller
//
// 2-cycle access: IDLE → ACCESS → IDLE
// req_ready deasserted during access, resp_valid for 1 cycle only
// ============================================================

module sram_ctrl (
    input  wire        clk,
    input  wire        clk_fast,
    input  wire        rst_n,

    input  wire        req_valid,
    output reg         req_ready,
    input  wire [31:0] req_addr,
    input  wire [31:0] req_wdata,
    input  wire [3:0]  req_wmask,
    input  wire        req_wen,
    output reg         resp_valid,
    output reg  [31:0] resp_rdata,

    output reg         sram_csn,
    output reg         sram_wen,
    output reg  [10:0] sram_addr,
    output reg  [31:0] sram_wdata,
    output reg  [3:0]  sram_wmask,
    input  wire [31:0] sram_rdata
);

    wire [10:0] word_addr = req_addr[12:2];

    localparam IDLE    = 2'd0;
    localparam ACCESS  = 2'd1;
    localparam RESPOND = 2'd2;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            req_ready  <= 1'b1;
            resp_valid <= 1'b0;
            resp_rdata <= 32'h0;
            sram_csn   <= 1'b1;
            sram_wen   <= 1'b1;
            sram_addr  <= 11'h0;
            sram_wdata <= 32'h0;
            sram_wmask <= 4'h0;
        end else begin
            case (state)
                IDLE: begin
                    resp_valid <= 1'b0;
                    if (req_valid && req_ready) begin
                        sram_csn   <= 1'b0;
                        sram_addr  <= word_addr;
                        sram_wen   <= ~req_wen;
                        sram_wdata <= req_wdata;
                        sram_wmask <= req_wmask;
                        req_ready  <= 1'b0;
                        state      <= ACCESS;
                    end
                end

                ACCESS: begin
                    // Data is now valid on sram_rdata
                    sram_csn   <= 1'b1;
                    sram_wen   <= 1'b1;
                    resp_valid <= 1'b1;
                    resp_rdata <= sram_rdata;
                    state      <= RESPOND;
                end

                RESPOND: begin
                    // Deassert resp_valid, then allow new requests
                    resp_valid <= 1'b0;
                    req_ready  <= 1'b1;
                    state      <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
