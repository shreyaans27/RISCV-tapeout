`timescale 1ns/1ps

module tb_top;

    reg pad_clk;
    reg rst_n;
    initial pad_clk = 0;
    always #5 pad_clk = ~pad_clk;

    wire jtag_tdo;
    wire [31:0] debug_pc;
    wire        debug_resp_valid;

    // SRAM macro signals
    wire        sram_den;
    wire [7:0]  sram_addr;
    wire [2:0]  sram_col_addr;
    wire        sram_prechg;
    wire        sram_ren;
    wire        sram_wen;
    wire        sram_en;
    wire [31:0] sram_din;
    reg  [31:0] sram_dout;

    // ROM macro signals
    wire [7:0]  rom_wl_addr;
    wire [3:0]  rom_col_in;
    wire        rom_preen;
    wire        rom_wlen;
    wire        rom_saen;
    reg  [31:0] rom_dout;

    // DUT
    core_top u_dut (
        .pad_clk        (pad_clk),
        .rst_n          (rst_n),
        .jtag_tck       (1'b0),
        .jtag_tms       (1'b0),
        .jtag_tdi       (1'b0),
        .jtag_tdo       (jtag_tdo),
        .sram_den       (sram_den),
        .sram_addr      (sram_addr),
        .sram_col_addr  (sram_col_addr),
        .sram_prechg    (sram_prechg),
        .sram_ren       (sram_ren),
        .sram_wen       (sram_wen),
        .sram_en        (sram_en),
        .sram_din       (sram_din),
        .sram_dout      (sram_dout),
        .rom_wl_addr    (rom_wl_addr),
        .rom_col_in     (rom_col_in),
        .rom_preen      (rom_preen),
        .rom_wlen       (rom_wlen),
        .rom_saen       (rom_saen),
        .rom_dout       (rom_dout),
        .debug_pc       (debug_pc),
        .debug_resp_valid(debug_resp_valid)
    );

    // --------------------------------------------------------
    // Behavioral SRAM model
    // --------------------------------------------------------
    reg [31:0] sram_mem [0:2047];
    wire [10:0] sram_word_addr = {sram_addr, sram_col_addr};

    always @(posedge sram_den) begin
        if (sram_wen && sram_prechg)
            sram_mem[sram_word_addr] <= sram_din;
    end

    always @(*) begin
        if (sram_den && sram_ren && sram_en && sram_prechg)
            sram_dout = sram_mem[sram_word_addr];
        else
            sram_dout = 32'h0;
    end

    // --------------------------------------------------------
    // Behavioral ROM model
    // Data pattern: (wl_addr[1:0] + col_in[1:0]) % 4
    //   0 → 0x00000000, 1 → 0x55555555
    //   2 → 0xAAAAAAAA, 3 → 0xFFFFFFFF
    // --------------------------------------------------------
    wire [1:0] rom_pattern = rom_wl_addr[1:0] + rom_col_in[1:0];

    always @(*) begin
        if (rom_saen && rom_wlen && !rom_preen) begin
            case (rom_pattern)
                2'd0: rom_dout = 32'h00000000;
                2'd1: rom_dout = 32'h55555555;
                2'd2: rom_dout = 32'hAAAAAAAA;
                2'd3: rom_dout = 32'hFFFFFFFF;
            endcase
        end else begin
            rom_dout = 32'h0;
        end
    end

    // --------------------------------------------------------
    // Load firmware
    // --------------------------------------------------------
    initial begin
        $readmemh("firmware.hex", sram_mem);
    end

    localparam DONE_WORD_ADDR = 11'h2CA;
    localparam RESULT_WORD_ADDR = 11'h2C8;

    integer cycle_count;

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);

        rst_n = 0;
        cycle_count = 0;
        #200;
        rst_n = 1;
        // Release core from JTAG control (bypass for regression testing)
        @(posedge u_dut.clk_25);
        u_dut.u_jtag.core_in_reset = 1'b0;
        u_dut.u_jtag.core_halted = 1'b0;
        $display("--- Reset released, core running ---");

        fork
            begin : watchdog
                #2000000;
                $display("ERROR: Timeout at cycle %0d", cycle_count);
                $display("  PC=0x%08x", debug_pc);
                $finish;
            end
            begin : wait_done
                @(posedge pad_clk);
                while (sram_mem[DONE_WORD_ADDR] !== 32'hFFFFFFFF)
                    @(posedge pad_clk);
                disable watchdog;
            end
        join

        #40;
        $display("--- Firmware completed at cycle %0d ---", cycle_count);
        $display("  DONE   = 0x%08x", sram_mem[DONE_WORD_ADDR]);
        $display("  RESULT = 0x%08x", sram_mem[RESULT_WORD_ADDR]);

        if (sram_mem[RESULT_WORD_ADDR] == 32'h00000001)
            $display("*** PASS ***");
        else
            $display("*** FAIL (expected 0x00000001, got 0x%08x) ***",
                sram_mem[RESULT_WORD_ADDR]);

        #100;
        $finish;
    end

    always @(posedge u_dut.clk_25) begin
        if (rst_n) cycle_count <= cycle_count + 1;
    end

endmodule
