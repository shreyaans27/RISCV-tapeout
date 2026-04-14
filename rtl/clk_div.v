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
