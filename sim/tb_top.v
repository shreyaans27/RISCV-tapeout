`timescale 1ns/1ps

module tb_top;

    // 200 MHz clock = 5ns period
    reg pad_clk;
    reg rst_n;
    initial pad_clk = 0;
    always #2.5 pad_clk = ~pad_clk;

    wire jtag_tdo;
    wire [31:0] debug_pc;
    wire        debug_resp_valid;

    // SRAM macro signals
    wire        sram_csn;
    wire        sram_wen;
    wire [10:0] sram_addr;
    wire [31:0] sram_wdata;
    wire [3:0]  sram_wmask;
    reg  [31:0] sram_rdata;

    // ROM macro signals
    wire        rom_en;
    wire [7:0]  rom_wl_addr;
    wire [3:0]  rom_col_addr;
    reg  [31:0] rom_rdata;

    // DUT
    core_top u_dut (
        .pad_clk        (pad_clk),
        .rst_n          (rst_n),
        .jtag_tck       (1'b0),
        .jtag_tms       (1'b0),
        .jtag_tdi       (1'b0),
        .jtag_tdo       (jtag_tdo),
        .sram_csn       (sram_csn),
        .sram_wen       (sram_wen),
        .sram_addr      (sram_addr),
        .sram_wdata     (sram_wdata),
        .sram_wmask     (sram_wmask),
        .sram_rdata     (sram_rdata),
        .rom_en         (rom_en),
        .rom_wl_addr    (rom_wl_addr),
        .rom_col_addr   (rom_col_addr),
        .rom_rdata      (rom_rdata),
        .debug_pc       (debug_pc),
        .debug_resp_valid(debug_resp_valid)
    );

    // --------------------------------------------------------
    // Behavioral SRAM model (external to DUT)
    // --------------------------------------------------------
    reg [31:0] sram_mem [0:2047];

    // Write: clocked on pad_clk
    always @(posedge pad_clk) begin
        if (!sram_csn && !sram_wen) begin
            if (sram_wmask[0]) sram_mem[sram_addr][ 7: 0] <= sram_wdata[ 7: 0];
            if (sram_wmask[1]) sram_mem[sram_addr][15: 8] <= sram_wdata[15: 8];
            if (sram_wmask[2]) sram_mem[sram_addr][23:16] <= sram_wdata[23:16];
            if (sram_wmask[3]) sram_mem[sram_addr][31:24] <= sram_wdata[31:24];
        end
    end

    // Read: combinational (data available immediately when csn asserted)
    always @(*) begin
        if (!sram_csn)
            sram_rdata = sram_mem[sram_addr];
        else
            sram_rdata = 32'h0;
    end

    // --------------------------------------------------------
    // Behavioral ROM model (external to DUT)
    // --------------------------------------------------------
    wire [1:0] rom_pattern = rom_wl_addr[1:0] + rom_col_addr[1:0];

    // Read: combinational (data available when rom_en asserted)
    always @(*) begin
        if (rom_en) begin
            case (rom_pattern)
                2'd0: rom_rdata = 32'h00000000;
                2'd1: rom_rdata = 32'h55555555;
                2'd2: rom_rdata = 32'hAAAAAAAA;
                2'd3: rom_rdata = 32'hFFFFFFFF;
            endcase
        end else begin
            rom_rdata = 32'h0;
        end
    end

    // --------------------------------------------------------
    // Load firmware into SRAM
    // --------------------------------------------------------
    initial begin
        $readmemh("firmware.hex", sram_mem);
    end

    // Monitor addresses
    localparam DONE_WORD_ADDR = 11'h2CA;    // 0xB28 >> 2
    localparam RESULT_WORD_ADDR = 11'h2C8;  // 0xB20 >> 2

    integer cycle_count;

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);

        rst_n = 0;
        cycle_count = 0;
        #200;  // longer reset for clock divider to stabilize
        rst_n = 1;
        $display("--- Reset released ---");

        fork
            begin : watchdog
                #2000000;  // longer timeout for slower effective clock
                $display("ERROR: Timeout at cycle %0d", cycle_count);
                $display("  PC=0x%08x", debug_pc);
                $finish;
            end
            begin : wait_done
                @(posedge pad_clk);
                while (sram_mem[DONE_WORD_ADDR][7:0] !== 8'hFF)
                    @(posedge pad_clk);
                disable watchdog;
            end
        join

        #40;
        $display("--- Firmware completed at cycle %0d ---", cycle_count);
        $display("  DONE   = 0x%02x", sram_mem[DONE_WORD_ADDR][7:0]);
        $display("  RESULT = 0x%02x", sram_mem[RESULT_WORD_ADDR][7:0]);

        if (sram_mem[RESULT_WORD_ADDR][7:0] == 8'h01)
            $display("*** PASS ***");
        else
            $display("*** FAIL (expected 0x01, got 0x%02x) ***",
                sram_mem[RESULT_WORD_ADDR][7:0]);

        #100;
        $finish;
    end

    // Count cycles on the core clock (clk_50)
    always @(posedge u_dut.clk_50) begin
        if (rst_n) cycle_count <= cycle_count + 1;
    end

endmodule
