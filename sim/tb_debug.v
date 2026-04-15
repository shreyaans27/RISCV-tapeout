`timescale 1ns/1ps

module tb_top;

    reg pad_clk;
    reg rst_n;
    initial pad_clk = 0;
    always #2.5 pad_clk = ~pad_clk;

    wire jtag_tdo;
    wire [31:0] debug_pc;
    wire        debug_resp_valid;

    wire        sram_den;
    wire [7:0]  sram_addr;
    wire [2:0]  sram_col_addr;
    wire        sram_prechg;
    wire        sram_ren;
    wire        sram_wen;
    wire        sram_en;
    wire [31:0] sram_din;
    reg  [31:0] sram_dout;

    wire        rom_en;
    wire [7:0]  rom_wl_addr;
    wire [3:0]  rom_col_addr;
    reg  [31:0] rom_rdata;

    core_top u_dut (
        .pad_clk(pad_clk), .rst_n(rst_n),
        .jtag_tck(1'b0), .jtag_tms(1'b0), .jtag_tdi(1'b0), .jtag_tdo(jtag_tdo),
        .sram_den(sram_den), .sram_addr(sram_addr), .sram_col_addr(sram_col_addr),
        .sram_prechg(sram_prechg), .sram_ren(sram_ren), .sram_wen(sram_wen),
        .sram_en(sram_en), .sram_din(sram_din), .sram_dout(sram_dout),
        .rom_en(rom_en), .rom_wl_addr(rom_wl_addr), .rom_col_addr(rom_col_addr),
        .rom_rdata(rom_rdata),
        .debug_pc(debug_pc), .debug_resp_valid(debug_resp_valid)
    );

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

    wire [1:0] rom_pattern = rom_wl_addr[1:0] + rom_col_addr[1:0];
    always @(*) begin
        if (rom_en) begin
            case (rom_pattern)
                2'd0: rom_rdata = 32'h00000000;
                2'd1: rom_rdata = 32'h55555555;
                2'd2: rom_rdata = 32'hAAAAAAAA;
                2'd3: rom_rdata = 32'hFFFFFFFF;
            endcase
        end else
            rom_rdata = 32'h0;
    end

    initial $readmemh("firmware.hex", sram_mem);

    integer cycle_count;

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);
        rst_n = 0;
        cycle_count = 0;
        #200;
        rst_n = 1;
        $display("--- Reset released ---");
        #10000;
        $finish;
    end

    always @(posedge u_dut.clk_50) begin
        if (rst_n) cycle_count <= cycle_count + 1;
    end

    // Trace every clk_50 cycle
    always @(posedge u_dut.clk_50) begin
        if (rst_n && cycle_count < 25) begin
            $display("[%0d] st=%0d PC=0x%08x rqv=%b rqr=%b rqa=0x%08x rsv=%b rsd=0x%08x | den=%b pchg=%b ren=%b wen=%b en=%b a=%02x c=%01x dout=0x%08x",
                cycle_count,
                u_dut.u_core.state,
                u_dut.u_core.pc,
                u_dut.u_core.req_valid,
                u_dut.u_core.req_ready,
                u_dut.u_core.req_addr,
                u_dut.u_core.resp_valid,
                u_dut.u_core.resp_rdata,
                sram_den, sram_prechg, sram_ren, sram_wen, sram_en,
                sram_addr, sram_col_addr, sram_dout);
        end
    end

endmodule
