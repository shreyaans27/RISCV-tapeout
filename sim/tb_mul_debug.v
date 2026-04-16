`timescale 1ns/1ps

module tb_mul_debug;

    reg pad_clk;
    reg rst_n;
    initial pad_clk = 0;
    always #2.5 pad_clk = ~pad_clk;

    wire jtag_tdo;
    wire [31:0] debug_pc;
    wire        debug_resp_valid;

    wire        sram_den, sram_prechg, sram_ren, sram_wen, sram_en;
    wire [7:0]  sram_addr;
    wire [2:0]  sram_col_addr;
    wire [31:0] sram_din;
    reg  [31:0] sram_dout;

    wire [7:0]  rom_wl_addr;
    wire [3:0]  rom_col_in;
    wire        rom_preen, rom_wlen, rom_saen;
    reg  [31:0] rom_dout;

    core_top u_dut (
        .pad_clk(pad_clk), .rst_n(rst_n),
        .jtag_tck(1'b0), .jtag_tms(1'b0), .jtag_tdi(1'b0), .jtag_tdo(jtag_tdo),
        .sram_den(sram_den), .sram_addr(sram_addr), .sram_col_addr(sram_col_addr),
        .sram_prechg(sram_prechg), .sram_ren(sram_ren), .sram_wen(sram_wen),
        .sram_en(sram_en), .sram_din(sram_din), .sram_dout(sram_dout),
        .rom_wl_addr(rom_wl_addr), .rom_col_in(rom_col_in),
        .rom_preen(rom_preen), .rom_wlen(rom_wlen), .rom_saen(rom_saen),
        .rom_dout(rom_dout),
        .debug_pc(debug_pc), .debug_resp_valid(debug_resp_valid)
    );

    // Behavioral SRAM
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

    // Behavioral ROM
    wire [1:0] rom_pattern = rom_wl_addr[1:0] + rom_col_in[1:0];
    always @(*) begin
        if (rom_saen && rom_wlen && !rom_preen)
            case (rom_pattern)
                2'd0: rom_dout = 32'h00000000;
                2'd1: rom_dout = 32'h55555555;
                2'd2: rom_dout = 32'hAAAAAAAA;
                2'd3: rom_dout = 32'hFFFFFFFF;
            endcase
        else
            rom_dout = 32'h0;
    end

    initial $readmemh("firmware_mul.hex", sram_mem);

    integer cycle_count;

    initial begin
        $dumpfile("mul_debug.vcd");
        $dumpvars(0, tb_mul_debug);
        rst_n = 0;
        cycle_count = 0;
        #200;
        rst_n = 1;
        $display("--- Reset released ---");
        #20000;
        $display("  RESULT = 0x%08x", sram_mem[11'h2C8]);
        $finish;
    end

    always @(posedge u_dut.clk_50) begin
        if (rst_n) cycle_count <= cycle_count + 1;
    end

    // Trace every clk_50 cycle with core internals
    always @(posedge u_dut.clk_50) begin
        if (rst_n && cycle_count < 80) begin
            $display("[%0d] st=%0d PC=0x%08x op=0x%02x rd=%0d rs1_d=0x%08x rs2_d=0x%08x alu_fast=0x%08x mul_reg=0x%08x | wr_en=%b wr_d=0x%08x",
                cycle_count,
                u_dut.u_core.state,
                u_dut.u_core.pc,
                u_dut.u_core.opcode,
                u_dut.u_core.rd,
                u_dut.u_core.rs1_data,
                u_dut.u_core.rs2_data,
                u_dut.u_core.alu_result_fast,
                u_dut.u_core.mul_result_reg,
                u_dut.u_core.rf_wr_en,
                u_dut.u_core.rf_wr_data);
        end
    end

endmodule
