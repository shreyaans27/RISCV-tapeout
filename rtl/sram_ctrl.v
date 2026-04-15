// ============================================================
// sram_ctrl.v — SRAM Controller with macro timing
//
// Posedge clk: bus handshake, stable SRAM signals, latch DOUT
// Negedge clk: transition PRECHG/DEN/EN high (10ns after posedge)
//
// Cycle 1 (IDLE→ACCESS): latch addr from bus, set stable pins
// Cycle 1 (negedge):     PRECHG↑, DEN↑, EN↑ — SRAM activates
// Cycle 2 (ACCESS→RESPOND): DOUT valid, latch it, assert resp_valid
// Cycle 3 (RESPOND→IDLE): deassert resp_valid, reassert req_ready
// ============================================================

module sram_ctrl (
    input  wire        clk,
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
    // Posedge domain: bus + stable SRAM pins + latch DOUT
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
            sram_ren      <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    resp_valid <= 1'b0;
                    sram_wen   <= 1'b0;
                    sram_ren   <= 1'b0;

                    if (req_valid && req_ready) begin
                        // Latch address and data
                        sram_addr     <= row_addr;
                        sram_col_addr <= col_addr;
                        sram_din      <= req_wdata;
                        sram_wen      <= req_wen;
                        sram_ren      <= ~req_wen;

                        req_ready <= 1'b0;
                        state     <= ACCESS;
                    end
                end

                ACCESS: begin
                    // At this posedge, the negedge already fired
                    // (DEN=1, PRECHG=1, EN=1) so DOUT is valid now
                    resp_rdata <= sram_dout;
                    resp_valid <= 1'b1;

                    // Deactivate stable pins
                    sram_wen <= 1'b0;
                    sram_ren <= 1'b0;

                    state <= RESPOND;
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
    // Negedge domain: transition signals
    // When state==ACCESS at negedge, assert DEN/PRECHG/EN
    // Otherwise keep them deasserted (precharge active)
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

endmodule
