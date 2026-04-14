// ============================================================
// rom_ctrl.v — ROM Controller
//
// 2-cycle access: IDLE → ACCESS → RESPOND → IDLE
// ============================================================

module rom_ctrl (
    input  wire        clk,
    input  wire        clk_fast,
    input  wire        rst_n,

    input  wire        req_valid,
    output reg         req_ready,
    input  wire [31:0] req_addr,
    output reg         resp_valid,
    output reg  [31:0] resp_rdata,

    output reg         rom_en,
    output reg  [7:0]  rom_wl_addr,
    output reg  [3:0]  rom_col_addr,
    input  wire [31:0] rom_rdata
);

    localparam IDLE    = 2'd0;
    localparam ACCESS  = 2'd1;
    localparam RESPOND = 2'd2;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            req_ready    <= 1'b1;
            resp_valid   <= 1'b0;
            resp_rdata   <= 32'h0;
            rom_en       <= 1'b0;
            rom_wl_addr  <= 8'h0;
            rom_col_addr <= 4'h0;
        end else begin
            case (state)
                IDLE: begin
                    resp_valid <= 1'b0;
                    if (req_valid && req_ready) begin
                        rom_en       <= 1'b1;
                        rom_wl_addr  <= req_addr[9:2];
                        rom_col_addr <= req_addr[13:10];
                        req_ready    <= 1'b0;
                        state        <= ACCESS;
                    end
                end

                ACCESS: begin
                    rom_en     <= 1'b0;
                    resp_valid <= 1'b1;
                    resp_rdata <= rom_rdata;
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

endmodule
