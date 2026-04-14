`timescale 1ns/1ps

module tb_top;

    reg pad_clk;
    reg rst_n;
    initial pad_clk = 0;
    always #2.5 pad_clk = ~pad_clk;

    wire jtag_tdo;
    wire [31:0] debug_pc;
    wire        debug_resp_valid;

    wire        sram_csn;
    wire        sram_wen;
    wire [10:0] sram_addr;
    wire [31:0] sram_wdata;
    wire [3:0]  sram_wmask;
    reg  [31:0] sram_rdata;

    wire        rom_en;
    wire [7:0]  rom_wl_addr;
    wire [3:0]  rom_col_addr;
    reg  [31:0] rom_rdata;

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

    // Behavioral SRAM
    reg [31:0] sram_mem [0:2047];

    always @(posedge pad_clk) begin
        if (!sram_csn && !sram_wen) begin
            if (sram_wmask[0]) sram_mem[sram_addr][ 7: 0] <= sram_wdata[ 7: 0];
            if (sram_wmask[1]) sram_mem[sram_addr][15: 8] <= sram_wdata[15: 8];
            if (sram_wmask[2]) sram_mem[sram_addr][23:16] <= sram_wdata[23:16];
            if (sram_wmask[3]) sram_mem[sram_addr][31:24] <= sram_wdata[31:24];
        end
    end
    always @(*) begin
        if (!sram_csn)
            sram_rdata = sram_mem[sram_addr];
        else
            sram_rdata = 32'h0;
    end

    // Behavioral ROM
    wire [1:0] rom_pattern = rom_wl_addr[1:0] + rom_col_addr[1:0];
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

    initial begin
        $readmemh("firmware.hex", sram_mem);
    end

    integer cycle_count;

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);

        rst_n = 0;
        cycle_count = 0;
        #200;
        rst_n = 1;
        $display("--- Reset released ---");

        #500000;
        $display("--- Stopping after 5us ---");
        $finish;
    end

    // Count on clk_50
    always @(posedge u_dut.clk_50) begin
        if (rst_n) cycle_count <= cycle_count + 1;
    end

    // Trace first 30 clk_50 cycles
    always @(posedge u_dut.clk_50) begin
        if (rst_n && cycle_count < 500 && cycle_count > 445) begin
            $display("[%0d] state=%0d PC=0x%08x req_valid=%b req_ready=%b req_addr=0x%08x resp_valid=%b resp_rdata=0x%08x | csn=%b wen=%b saddr=0x%03x srdata=0x%08x",
                cycle_count,
                u_dut.u_core.state,
                u_dut.u_core.pc,
                u_dut.u_core.req_valid,
                u_dut.u_core.req_ready,
                u_dut.u_core.req_addr,
                u_dut.u_core.resp_valid,
                u_dut.u_core.resp_rdata,
                sram_csn, sram_wen, sram_addr, sram_rdata);
        end
    end

endmodule
