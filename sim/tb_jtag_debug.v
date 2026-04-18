`timescale 1ns/1ps

module tb_jtag_debug;

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

    // SRAM model
    reg [31:0] sram_mem [0:2047];
    wire [10:0] sram_word_addr = {sram_addr, sram_col_addr};
    always @(posedge sram_den) begin
        if (sram_wen && sram_prechg) sram_mem[sram_word_addr] <= sram_din;
    end
    always @(*) begin
        if (sram_den && sram_ren && sram_en && sram_prechg) sram_dout = sram_mem[sram_word_addr];
        else sram_dout = 32'h0;
    end

    // ROM model
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

    task jtag_clock;
        begin #TCK_HALF; jtag_tck = 1; #TCK_HALF; jtag_tck = 0; end
    endtask

    task jtag_reset;
        begin
            jtag_tms = 1; repeat(5) jtag_clock;
            jtag_tms = 0; jtag_clock;
        end
    endtask

    task goto_shift_ir;
        begin jtag_tms=1; jtag_clock; jtag_tms=1; jtag_clock; jtag_tms=0; jtag_clock; jtag_tms=0; jtag_clock; end
    endtask

    task goto_shift_dr;
        begin jtag_tms=1; jtag_clock; jtag_tms=0; jtag_clock; jtag_tms=0; jtag_clock; end
    endtask

    task goto_rti;
        begin jtag_tms=1; jtag_clock; jtag_tms=0; jtag_clock; end
    endtask

    // Write IR
    task write_ir;
        input [2:0] val;
        integer i;
        begin
            goto_shift_ir;
            for (i = 0; i < 3; i = i + 1) begin
                jtag_tdi = val[i];
                jtag_tms = (i == 2) ? 1 : 0;
                jtag_clock;
            end
            goto_rti;
        end
    endtask

    // Shift 68-bit DR
    task shift_dr_68;
        input [67:0] din;
        output [67:0] dout;
        integer i;
        begin
            goto_shift_dr;
            dout = 68'h0;
            for (i = 0; i < 68; i = i + 1) begin
                jtag_tdi = din[i];
                jtag_tms = (i == 67) ? 1 : 0;
                jtag_clock;
                dout[i] = jtag_tdo;
            end
            goto_rti;
        end
    endtask

    reg [67:0] resp;

    initial begin
        $dumpfile("jtag_debug.vcd");
        $dumpvars(0, tb_jtag_debug);

        jtag_tck = 0; jtag_tms = 1; jtag_tdi = 0;
        rst_n = 0;
        #500; rst_n = 1; #500;

        jtag_reset;
        write_ir(3'b010);  // DATA_REG

        // Send RESET control command
        $display("--- Sending CORE_RESET ---");
        shift_dr_68({2'b10, 32'h0, 32'h00000001, 2'b00}, resp);
        #2000;

        // Write word 0 to SRAM
        $display("--- Writing 0xAABBCCDD to 0x08000000 ---");
        shift_dr_68({2'b01, 32'h08000000, 32'hAABBCCDD, 2'b00}, resp);
        #5000;

        // Monitor bus master state
        $display("  bus_state=%0d bus_status=%0b trigger_toggle=%b sync2=%b sync3=%b",
            u_dut.u_jtag.bus_state,
            u_dut.u_jtag.bus_status,
            u_dut.u_jtag.update_toggle,
            u_dut.u_jtag.sync2,
            u_dut.u_jtag.sync3);
        $display("  cmd_reg=%0b addr_reg=0x%08x wdata_reg=0x%08x",
            u_dut.u_jtag.cmd_reg,
            u_dut.u_jtag.addr_reg,
            u_dut.u_jtag.wdata_reg);
        $display("  req_valid=%b req_addr=0x%08x req_wen=%b",
            u_dut.u_jtag.req_valid,
            u_dut.u_jtag.req_addr,
            u_dut.u_jtag.req_wen);
        $display("  sram_mem[0]=0x%08x", sram_mem[0]);

        // Write word 1
        $display("\n--- Writing 0x11223344 to 0x08000004 ---");
        shift_dr_68({2'b01, 32'h08000004, 32'h11223344, 2'b00}, resp);
        #5000;

        $display("  bus_state=%0d bus_status=%0b",
            u_dut.u_jtag.bus_state, u_dut.u_jtag.bus_status);
        $display("  cmd_reg=%0b addr_reg=0x%08x wdata_reg=0x%08x",
            u_dut.u_jtag.cmd_reg,
            u_dut.u_jtag.addr_reg,
            u_dut.u_jtag.wdata_reg);
        $display("  sram_mem[0]=0x%08x sram_mem[1]=0x%08x", sram_mem[0], sram_mem[1]);

        // Read word 0
        $display("\n--- Reading 0x08000000 ---");
        shift_dr_68({2'b00, 32'h08000000, 32'h0, 2'b00}, resp);
        #5000;
        $display("  last_rdata=0x%08x", u_dut.u_jtag.last_rdata);

        // Capture and shift out
        shift_dr_68(68'h0, resp);
        $display("  Read back: status=%0b rdata=0x%08x pc=0x%08x state=%0b",
            resp[67:66], resp[65:34], resp[33:2], resp[1:0]);

        $display("\n--- Done ---");
        $finish;
    end

endmodule
