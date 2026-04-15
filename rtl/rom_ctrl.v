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
