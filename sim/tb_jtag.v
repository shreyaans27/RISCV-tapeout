`timescale 1ns/1ps

module tb_jtag;

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

    // ========================================================
    // JTAG tasks
    // ========================================================
    localparam TCK_HALF = 200;
    task jtag_clock; begin #TCK_HALF; jtag_tck=1; #TCK_HALF; jtag_tck=0; end endtask
    task jtag_reset; begin jtag_tms=1; repeat(5) jtag_clock; jtag_tms=0; jtag_clock; end endtask
    task goto_shift_ir; begin jtag_tms=1; jtag_clock; jtag_tms=1; jtag_clock; jtag_tms=0; jtag_clock; jtag_tms=0; jtag_clock; end endtask
    task goto_shift_dr; begin jtag_tms=1; jtag_clock; jtag_tms=0; jtag_clock; jtag_tms=0; jtag_clock; end endtask
    task goto_rti; begin jtag_tms=1; jtag_clock; jtag_tms=0; jtag_clock; end endtask

    task write_ir;
        input [2:0] val; integer i;
        begin
            goto_shift_ir;
            for (i=0; i<3; i=i+1) begin jtag_tdi=val[i]; jtag_tms=(i==2)?1:0; jtag_clock; end
            goto_rti;
        end
    endtask

    reg [67:0] shift_resp;

    task shift_dr_68;
        input [67:0] din; output [67:0] dout; integer i;
        begin
            goto_shift_dr; dout=68'h0;
            for (i=0; i<68; i=i+1) begin jtag_tdi=din[i]; jtag_tms=(i==67)?1:0; jtag_clock; dout[i]=jtag_tdo; end
            goto_rti;
        end
    endtask

    task shift_dr_32;
        output [31:0] dout; integer i; reg [67:0] tmp;
        begin
            goto_shift_dr; tmp=68'h0;
            for (i=0; i<32; i=i+1) begin jtag_tdi=0; jtag_tms=(i==31)?1:0; jtag_clock; tmp[i]=jtag_tdo; end
            dout=tmp[31:0]; goto_rti;
        end
    endtask

    task shift_dr_1;
        input din; output dout;
        begin
            goto_shift_dr;
            jtag_tdi=din; jtag_tms=1; jtag_clock; dout=jtag_tdo;
            goto_rti;
        end
    endtask

    task jtag_write_mem;
        input [31:0] addr; input [31:0] data; reg [67:0] resp;
        begin shift_dr_68({2'b01, addr, data, 2'b00}, resp); #5000; end
    endtask

    task jtag_read_mem;
        input [31:0] addr; output [31:0] data; reg [67:0] resp;
        begin
            shift_dr_68({2'b00, addr, 32'h0, 2'b00}, resp); #5000;
            shift_dr_68({2'b11, 32'h0, 32'h0, 2'b00}, resp); data=resp[65:34];
        end
    endtask

    task jtag_control;
        input [3:0] ctrl; reg [67:0] resp;
        begin shift_dr_68({2'b10, 32'h0, {28'h0, ctrl}, 2'b00}, resp); #5000; end
    endtask

    task jtag_read_status;
        output [1:0] status; output [31:0] rdata; output [31:0] pc; output [1:0] cstate;
        reg [67:0] resp;
        begin
            shift_dr_68({2'b11, 32'h0, 32'h0, 2'b00}, resp);
            status = resp[67:66]; rdata = resp[65:34]; pc = resp[33:2]; cstate = resp[1:0];
        end
    endtask

    // Firmware (compiler-verified)
    reg [31:0] fw [0:16];
    initial begin
        fw[0]  = 32'h00700313;
        fw[1]  = 32'h00600393;
        fw[2]  = 32'h02730e33;
        fw[3]  = 32'h08001437;
        fw[4]  = 32'hb2040413;
        fw[5]  = 32'h080014b7;
        fw[6]  = 32'hb2848493;
        fw[7]  = 32'h02a00e93;
        fw[8]  = 32'h01de1c63;
        fw[9]  = 32'h00100293;
        fw[10] = 32'h00542023;
        fw[11] = 32'hfff00293;
        fw[12] = 32'h0054a023;
        fw[13] = 32'h00c0006f;
        fw[14] = 32'hfff00293;
        fw[15] = 32'h0054a023;
        fw[16] = 32'h0000006f;
    end

    integer i, pass_count, fail_count, test_num;
    reg [31:0] read_data;
    reg [1:0] status;
    reg [31:0] rdata, pc_val;
    reg [1:0] cstate;
    reg bypass_out;

    initial begin
        $dumpfile("jtag_test.vcd");
        $dumpvars(0, tb_jtag);
        jtag_tck=0; jtag_tms=1; jtag_tdi=0; rst_n=0;
        pass_count=0; fail_count=0;
        #500; rst_n=1; #500;

        jtag_reset;
        write_ir(3'b010);

        // ====================================================
        // Test 1: IDCODE
        // ====================================================
        test_num = 1;
        $display("\n=== Test %0d: IDCODE ===", test_num);
        write_ir(3'b001);
        shift_dr_32(read_data);
        write_ir(3'b010);
        if (read_data == 32'hDEAD0001) begin
            $display("  PASS: 0x%08x", read_data); pass_count=pass_count+1;
        end else begin
            $display("  FAIL: 0x%08x", read_data); fail_count=fail_count+1;
        end

        // ====================================================
        // Test 2: BYPASS
        // ====================================================
        test_num = 2;
        $display("\n=== Test %0d: BYPASS ===", test_num);
        write_ir(3'b000);
        shift_dr_1(1'b1, bypass_out);
        // BYPASS delays TDI by 1 bit, so first shift out is 0 (captured)
        // Second shift should echo what we sent
        shift_dr_1(1'b0, bypass_out);
        write_ir(3'b010);
        if (bypass_out == 1'b1) begin
            $display("  PASS: BYPASS echoed correctly"); pass_count=pass_count+1;
        end else begin
            $display("  FAIL: BYPASS got %b", bypass_out); fail_count=fail_count+1;
        end

        // ====================================================
        // Test 3: SRAM Write/Read
        // ====================================================
        test_num = 3;
        $display("\n=== Test %0d: SRAM Write/Read ===", test_num);
        jtag_control(4'b0001);  // RESET
        for (i = 0; i < 17; i = i + 1)
            jtag_write_mem(32'h08000000 + (i*4), fw[i]);

        begin : verify_sram
            integer ok;
            ok = 1;
            for (i = 0; i < 17; i = i + 1) begin
                jtag_read_mem(32'h08000000 + (i*4), read_data);
                if (read_data !== fw[i]) begin
                    $display("  FAIL: [%0d] got 0x%08x exp 0x%08x", i, read_data, fw[i]);
                    ok = 0;
                end
            end
            if (ok) begin $display("  PASS: 17 words verified"); pass_count=pass_count+1; end
            else fail_count=fail_count+1;
        end

        // ====================================================
        // Test 4: Core Free-Run
        // ====================================================
        test_num = 4;
        $display("\n=== Test %0d: Core Free-Run ===", test_num);
        jtag_control(4'b0010);  // RELEASE
        begin : poll_run
            integer timeout; timeout = 0; read_data = 0;
            while (read_data !== 32'hFFFFFFFF && timeout < 50) begin
                #50000;
                jtag_read_mem(32'h08000B28, read_data);
                timeout = timeout + 1;
            end
            if (read_data == 32'hFFFFFFFF) begin
                jtag_read_mem(32'h08000B20, read_data);
                if (read_data == 32'h00000001) begin
                    $display("  PASS: RESULT=0x%08x", read_data); pass_count=pass_count+1;
                end else begin
                    $display("  FAIL: RESULT=0x%08x", read_data); fail_count=fail_count+1;
                end
            end else begin
                $display("  FAIL: Timeout"); fail_count=fail_count+1;
            end
        end

        // ====================================================
        // Test 5: Single-Step with PC verification
        // ====================================================
        test_num = 5;
        $display("\n=== Test %0d: Single-Step ===", test_num);
        jtag_control(4'b0001);  // RESET
        #2000;

        // Write simple firmware: just NOPs
        jtag_write_mem(32'h08000000, 32'h00000013);  // nop (addi x0,x0,0)
        jtag_write_mem(32'h08000004, 32'h00000013);  // nop
        jtag_write_mem(32'h08000008, 32'h00000013);  // nop
        jtag_write_mem(32'h0800000C, 32'h0000006f);  // j self

        // Step 1
        jtag_control(4'b0100);  // STEP
        #10000;
        jtag_read_status(status, rdata, pc_val, cstate);
        $display("  Step 1: PC=0x%08x state=%02b", pc_val, cstate);

        // Step multiple times to get through fetch+execute
        repeat(10) begin
            jtag_control(4'b0100);
            #10000;
        end
        jtag_read_status(status, rdata, pc_val, cstate);
        $display("  After 11 steps: PC=0x%08x state=%02b", pc_val, cstate);

        if (pc_val > 32'h08000000) begin
            $display("  PASS: PC advanced"); pass_count=pass_count+1;
        end else begin
            $display("  FAIL: PC did not advance"); fail_count=fail_count+1;
        end

        // ====================================================
        // Test 6: HALT while running, then resume
        // ====================================================
        test_num = 6;
        $display("\n=== Test %0d: HALT and Resume ===", test_num);
        jtag_control(4'b0001);  // RESET
        #2000;

        // Rewrite MUL firmware
        for (i = 0; i < 17; i = i + 1)
            jtag_write_mem(32'h08000000 + (i*4), fw[i]);
        // Clear result
        jtag_write_mem(32'h08000B20, 32'h0);
        jtag_write_mem(32'h08000B28, 32'h0);

        // Release and let run briefly
        jtag_control(4'b0010);  // RELEASE
        #100000;  // run for 100us

        // HALT
        jtag_control(4'b1000);  // HALT
        #5000;
        jtag_read_status(status, rdata, pc_val, cstate);
        $display("  After HALT: PC=0x%08x state=%02b", pc_val, cstate);

        if (cstate == 2'b01) begin
            $display("  Core is halted");
        end else begin
            $display("  WARNING: Core state=%02b (expected halted=01)", cstate);
        end

        // Resume
        jtag_control(4'b0010);  // RELEASE
        begin : poll_resume
            integer timeout; timeout = 0; read_data = 0;
            while (read_data !== 32'hFFFFFFFF && timeout < 50) begin
                #50000;
                jtag_read_mem(32'h08000B28, read_data);
                timeout = timeout + 1;
            end
            if (read_data == 32'hFFFFFFFF) begin
                jtag_read_mem(32'h08000B20, read_data);
                if (read_data == 32'h00000001) begin
                    $display("  PASS: Resume completed, RESULT=0x%08x", read_data);
                    pass_count=pass_count+1;
                end else begin
                    $display("  FAIL: RESULT=0x%08x after resume", read_data);
                    fail_count=fail_count+1;
                end
            end else begin
                $display("  FAIL: Timeout after resume"); fail_count=fail_count+1;
            end
        end

        // ====================================================
        // Test 7: ROM Read (characterization)
        // ====================================================
        test_num = 7;
        $display("\n=== Test %0d: ROM Read ===", test_num);
        jtag_control(4'b0001);  // RESET
        #2000;

        begin : rom_test
            integer ok;
            reg [31:0] rv;
            ok = 1;

            jtag_read_mem(32'h20000000, rv);
            $display("  ROM[WL=0,COL=0]=0x%08x (exp 0x00000000)", rv);
            if (rv !== 32'h00000000) ok=0;

            jtag_read_mem(32'h20000004, rv);
            $display("  ROM[WL=1,COL=0]=0x%08x (exp 0x55555555)", rv);
            if (rv !== 32'h55555555) ok=0;

            jtag_read_mem(32'h20000008, rv);
            $display("  ROM[WL=2,COL=0]=0x%08x (exp 0xAAAAAAAA)", rv);
            if (rv !== 32'hAAAAAAAA) ok=0;

            jtag_read_mem(32'h2000000C, rv);
            $display("  ROM[WL=3,COL=0]=0x%08x (exp 0xFFFFFFFF)", rv);
            if (rv !== 32'hFFFFFFFF) ok=0;

            jtag_read_mem(32'h20000400, rv);
            $display("  ROM[WL=0,COL=1]=0x%08x (exp 0x55555555)", rv);
            if (rv !== 32'h55555555) ok=0;

            if (ok) begin $display("  PASS: ROM correct"); pass_count=pass_count+1; end
            else begin $display("  FAIL: ROM mismatch"); fail_count=fail_count+1; end
        end

        // ====================================================
        // Test 8: TAP Reset Recovery
        // ====================================================
        test_num = 8;
        $display("\n=== Test %0d: TAP Reset Recovery ===", test_num);
        // Force TAP to TLR
        jtag_tms = 1; repeat(5) jtag_clock;
        jtag_tms = 0; jtag_clock;  // back to RTI

        // Should still work — read IDCODE
        write_ir(3'b001);
        shift_dr_32(read_data);
        write_ir(3'b010);
        if (read_data == 32'hDEAD0001) begin
            $display("  PASS: IDCODE after reset=0x%08x", read_data); pass_count=pass_count+1;
        end else begin
            $display("  FAIL: IDCODE=0x%08x", read_data); fail_count=fail_count+1;
        end

        // ====================================================
        // Summary
        // ====================================================
        $display("\n========================================");
        $display("JTAG Tests: %0d PASS, %0d FAIL (of %0d)", pass_count, fail_count, test_num);
        if (fail_count == 0)
            $display("*** ALL TESTS PASSED ***");
        else
            $display("*** %0d FAILED ***", fail_count);
        $display("========================================\n");

        #1000;
        $finish;
    end

endmodule
