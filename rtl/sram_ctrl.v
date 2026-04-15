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
