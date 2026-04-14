`timescale 1ns/1ps

module tb_top;

    reg clk;
    reg rst_n;

    initial clk = 0;
    always #10 clk = ~clk;

    wire jtag_tdo;

    core_top u_dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .jtag_tck   (1'b0),
        .jtag_tms   (1'b0),
        .jtag_tdi   (1'b0),
        .jtag_tdo   (jtag_tdo)
    );

    initial begin
        $readmemh("firmware.hex", u_dut.u_sram.mem);
    end

    // DONE_ADDR = 0x08000B28, word addr = 0xB28 >> 2 = 0x2CA
    // RESULT_ADDR = 0x08000B20, word addr = 0xB20 >> 2 = 0x2C8
    localparam DONE_WORD_ADDR = 11'h2CA;
    localparam RESULT_WORD_ADDR = 11'h2C8;

    integer cycle_count;

    initial begin
        $dumpfile("tb_top.vcd");
        $dumpvars(0, tb_top);

        rst_n = 0;
        cycle_count = 0;
        #100;
        rst_n = 1;
        $display("--- Reset released ---");

        fork
            begin : watchdog
                #200000;
                $display("ERROR: Timeout at cycle %0d", cycle_count);
                $display("  PC=0x%08x state=%0d", u_dut.u_core.pc, u_dut.u_core.state);
                $finish;
            end
            begin : wait_done
                @(posedge clk);
                while (u_dut.u_sram.mem[DONE_WORD_ADDR][7:0] !== 8'hFF)
                    @(posedge clk);
                disable watchdog;
            end
        join

        #20; // let last write complete
        $display("--- Firmware completed at cycle %0d ---", cycle_count);
        $display("  DONE   = 0x%02x", u_dut.u_sram.mem[DONE_WORD_ADDR][7:0]);
        $display("  RESULT = 0x%02x", u_dut.u_sram.mem[RESULT_WORD_ADDR][7:0]);

        if (u_dut.u_sram.mem[RESULT_WORD_ADDR][7:0] == 8'h01)
            $display("*** PASS ***");
        else
            $display("*** FAIL (expected 0x01, got 0x%02x) ***",
                u_dut.u_sram.mem[RESULT_WORD_ADDR][7:0]);

        #100;
        $finish;
    end

    always @(posedge clk) begin
        if (rst_n) cycle_count <= cycle_count + 1;
    end

endmodule
