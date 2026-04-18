`timescale 1ns/1ps

module tb_jtag_rom2;

    reg pad_clk;
    reg rst_n;
    initial pad_clk = 0;
    always #5 pad_clk = ~pad_clk;

    reg  jtag_tck, jtag_tms, jtag_tdi;
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
        .jtag_tck(jtag_tck), .jtag_tms(jtag_tms), .jtag_tdi(jtag_tdi), .jtag_tdo(jtag_tdo),
        .sram_den(sram_den), .sram_addr(sram_addr), .sram_col_addr(sram_col_addr),
        .sram_prechg(sram_prechg), .sram_ren(sram_ren), .sram_wen(sram_wen),
        .sram_en(sram_en), .sram_din(sram_din), .sram_dout(sram_dout),
        .rom_wl_addr(rom_wl_addr), .rom_col_in(rom_col_in),
        .rom_preen(rom_preen), .rom_wlen(rom_wlen), .rom_saen(rom_saen),
        .rom_dout(rom_dout),
        .debug_pc(debug_pc), .debug_resp_valid(debug_resp_valid)
    );

    // SRAM
    reg [31:0] sram_mem [0:2047];
    wire [10:0] sram_word_addr = {sram_addr, sram_col_addr};
    always @(posedge sram_den) begin
        if (sram_wen && sram_prechg) sram_mem[sram_word_addr] <= sram_din;
    end
    always @(*) begin
        if (sram_den && sram_ren && sram_en && sram_prechg) sram_dout = sram_mem[sram_word_addr];
        else sram_dout = 32'h0;
    end

    // ROM
    wire [1:0] rom_pattern = rom_wl_addr[1:0] + rom_col_in[1:0];
    always @(*) begin
        if (rom_saen && rom_wlen && !rom_preen)
            case (rom_pattern)
                2'd0: rom_dout = 32'h00000000;
                2'd1: rom_dout = 32'h55555555;
                2'd2: rom_dout = 32'hAAAAAAAA;
                2'd3: rom_dout = 32'hFFFFFFFF;
            endcase
        else rom_dout = 32'h0;
    end

    localparam TCK_HALF = 200;
    task jtag_clock; begin #TCK_HALF; jtag_tck=1; #TCK_HALF; jtag_tck=0; end endtask
    task jtag_reset; begin jtag_tms=1; repeat(5) jtag_clock; jtag_tms=0; jtag_clock; end endtask
    task goto_shift_ir; begin jtag_tms=1; jtag_clock; jtag_tms=1; jtag_clock; jtag_tms=0; jtag_clock; jtag_tms=0; jtag_clock; end endtask
    task goto_shift_dr; begin jtag_tms=1; jtag_clock; jtag_tms=0; jtag_clock; jtag_tms=0; jtag_clock; end endtask
    task goto_rti; begin jtag_tms=1; jtag_clock; jtag_tms=0; jtag_clock; end endtask
    task write_ir; input [2:0] val; integer i; begin
        goto_shift_ir;
        for (i=0; i<3; i=i+1) begin jtag_tdi=val[i]; jtag_tms=(i==2)?1:0; jtag_clock; end
        goto_rti;
    end endtask
    task shift_dr_68; input [67:0] din; output [67:0] dout; integer i; begin
        goto_shift_dr; dout=68'h0;
        for (i=0; i<68; i=i+1) begin jtag_tdi=din[i]; jtag_tms=(i==67)?1:0; jtag_clock; dout[i]=jtag_tdo; end
        goto_rti;
    end endtask

    reg [67:0] resp;

    initial begin
        $dumpfile("jtag_rom2.vcd");
        $dumpvars(0, tb_jtag_rom2);
        jtag_tck=0; jtag_tms=1; jtag_tdi=0; rst_n=0;
        #500; rst_n=1; #500;

        jtag_reset;
        write_ir(3'b010);

        // Reset core
        shift_dr_68({2'b10, 32'h0, 32'h00000001, 2'b00}, resp);
        #5000;

        // ROM read: 0x20000004
        $display("--- ROM read 0x20000004 ---");
        shift_dr_68({2'b00, 32'h20000004, 32'h0, 2'b00}, resp);
        $display("  Immediate capture: status=%b rdata=0x%08x", resp[67:66], resp[65:34]);

        // Wait and monitor
        repeat(200) begin
            @(posedge u_dut.clk_25);
        end

        $display("  After wait: bus_state=%0d bus_status=%b last_rdata=0x%08x",
            u_dut.u_jtag.bus_state, u_dut.u_jtag.bus_status, u_dut.u_jtag.last_rdata);
        $display("  xbar s1_owner=%0d m1_req_valid=%b m1_resp_valid=%b",
            u_dut.u_xbar.s1_owner,
            u_dut.u_xbar.m1_req_valid,
            u_dut.u_xbar.m1_resp_valid);
        $display("  rom_ctrl: state=%0d req_valid=%b req_ready=%b resp_valid=%b",
            u_dut.u_rom.state,
            u_dut.u_xbar.s1_req_valid,
            u_dut.u_xbar.s1_req_ready,
            u_dut.u_xbar.s1_resp_valid);

        // NOP capture
        shift_dr_68({2'b11, 32'h0, 32'h0, 2'b00}, resp);
        $display("  NOP capture: status=%b rdata=0x%08x", resp[67:66], resp[65:34]);

        $finish;
    end
endmodule
