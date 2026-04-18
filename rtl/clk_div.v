// ============================================================
// clk_div.v — 3-stage divide-by-2 frequency divider
//
// Input:  pad_clk (100 MHz)
// Output: clk_50  (50 MHz)
//         clk_25  (25 MHz) — core, JTAG, bus
// ============================================================

module clk_div (
    input  wire pad_clk,
    input  wire rst_n,
    output wire clk_50,
    output wire clk_25
);

    // Stage 1: 100 → 50 MHz
    reg div2_reg;
    always @(posedge pad_clk or negedge rst_n) begin
        if (!rst_n)
            div2_reg <= 1'b0;
        else
            div2_reg <= ~div2_reg;
    end
    assign clk_50 = div2_reg;

    // Stage 2: 50 → 25 MHz
    reg div4_reg;
    always @(posedge clk_50 or negedge rst_n) begin
        if (!rst_n)
            div4_reg <= 1'b0;
        else
            div4_reg <= ~div4_reg;
    end
    assign clk_25 = div4_reg;

endmodule
