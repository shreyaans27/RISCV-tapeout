// ============================================================
// jtag_bridge.v — JTAG TAP + Bus Master + Core Control
//
// TAP, IR, shift registers: posedge jtag_tck
// Bus master, core control: posedge clk (clk_25)
// CDC: toggle synchronizer TCK → clk_25
//
// TCK is slower than clk_25, so cmd/addr/wdata set in TCK domain
// are stable well before the CDC trigger arrives in clk_25 domain.
// ============================================================

module jtag_bridge (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        jtag_tck,
    input  wire        jtag_tms,
    input  wire        jtag_tdi,
    output wire        jtag_tdo,

    output wire        core_rst_n,
    output wire        core_clk_en,

    output reg         req_valid,
    input  wire        req_ready,
    output reg  [31:0] req_addr,
    output reg  [31:0] req_wdata,
    output reg  [3:0]  req_wmask,
    output reg         req_wen,
    input  wire        resp_valid,
    input  wire [31:0] resp_rdata,

    input  wire [31:0] debug_pc
);

    localparam IDCODE_VAL = 32'hDEAD0001;

    // ========================================================
    // TAP State Machine (posedge jtag_tck)
    // ========================================================
    localparam TAP_TLR       = 4'd0;
    localparam TAP_RTI       = 4'd1;
    localparam TAP_SEL_DR    = 4'd2;
    localparam TAP_CAP_DR    = 4'd3;
    localparam TAP_SHIFT_DR  = 4'd4;
    localparam TAP_EXIT1_DR  = 4'd5;
    localparam TAP_PAUSE_DR  = 4'd6;
    localparam TAP_EXIT2_DR  = 4'd7;
    localparam TAP_UPDATE_DR = 4'd8;
    localparam TAP_SEL_IR    = 4'd9;
    localparam TAP_CAP_IR    = 4'd10;
    localparam TAP_SHIFT_IR  = 4'd11;
    localparam TAP_EXIT1_IR  = 4'd12;
    localparam TAP_PAUSE_IR  = 4'd13;
    localparam TAP_EXIT2_IR  = 4'd14;
    localparam TAP_UPDATE_IR = 4'd15;

    reg [3:0] tap_state;

    always @(posedge jtag_tck or negedge rst_n) begin
        if (!rst_n)
            tap_state <= TAP_TLR;
        else begin
            case (tap_state)
                TAP_TLR:       tap_state <= jtag_tms ? TAP_TLR       : TAP_RTI;
                TAP_RTI:       tap_state <= jtag_tms ? TAP_SEL_DR    : TAP_RTI;
                TAP_SEL_DR:    tap_state <= jtag_tms ? TAP_SEL_IR    : TAP_CAP_DR;
                TAP_CAP_DR:    tap_state <= jtag_tms ? TAP_EXIT1_DR  : TAP_SHIFT_DR;
                TAP_SHIFT_DR:  tap_state <= jtag_tms ? TAP_EXIT1_DR  : TAP_SHIFT_DR;
                TAP_EXIT1_DR:  tap_state <= jtag_tms ? TAP_UPDATE_DR : TAP_PAUSE_DR;
                TAP_PAUSE_DR:  tap_state <= jtag_tms ? TAP_EXIT2_DR  : TAP_PAUSE_DR;
                TAP_EXIT2_DR:  tap_state <= jtag_tms ? TAP_UPDATE_DR : TAP_SHIFT_DR;
                TAP_UPDATE_DR: tap_state <= jtag_tms ? TAP_SEL_DR    : TAP_RTI;
                TAP_SEL_IR:    tap_state <= jtag_tms ? TAP_TLR       : TAP_CAP_IR;
                TAP_CAP_IR:    tap_state <= jtag_tms ? TAP_EXIT1_IR  : TAP_SHIFT_IR;
                TAP_SHIFT_IR:  tap_state <= jtag_tms ? TAP_EXIT1_IR  : TAP_SHIFT_IR;
                TAP_EXIT1_IR:  tap_state <= jtag_tms ? TAP_UPDATE_IR : TAP_PAUSE_IR;
                TAP_PAUSE_IR:  tap_state <= jtag_tms ? TAP_EXIT2_IR  : TAP_PAUSE_IR;
                TAP_EXIT2_IR:  tap_state <= jtag_tms ? TAP_UPDATE_IR : TAP_SHIFT_IR;
                TAP_UPDATE_IR: tap_state <= jtag_tms ? TAP_SEL_DR    : TAP_RTI;
            endcase
        end
    end

    // ========================================================
    // Instruction Register (3 bits, posedge jtag_tck)
    // ========================================================
    localparam IR_BYPASS = 3'b000;
    localparam IR_IDCODE = 3'b001;
    localparam IR_DATA   = 3'b010;

    reg [2:0] ir_shift, ir_reg;

    always @(posedge jtag_tck or negedge rst_n) begin
        if (!rst_n) begin
            ir_shift <= 3'b0;
            ir_reg   <= IR_IDCODE;
        end else begin
            case (tap_state)
                TAP_CAP_IR:    ir_shift <= ir_reg;
                TAP_SHIFT_IR:  ir_shift <= {jtag_tdi, ir_shift[2:1]};
                TAP_UPDATE_IR: ir_reg   <= ir_shift;
                TAP_TLR:       ir_reg   <= IR_IDCODE;
                default: ;
            endcase
        end
    end

    // ========================================================
    // BYPASS Register (posedge jtag_tck)
    // ========================================================
    reg bypass_reg;
    always @(posedge jtag_tck or negedge rst_n) begin
        if (!rst_n)
            bypass_reg <= 1'b0;
        else if (tap_state == TAP_SHIFT_DR && ir_reg == IR_BYPASS)
            bypass_reg <= jtag_tdi;
    end

    // ========================================================
    // IDCODE Register (32 bits, posedge jtag_tck)
    // ========================================================
    reg [31:0] idcode_shift;
    always @(posedge jtag_tck or negedge rst_n) begin
        if (!rst_n)
            idcode_shift <= IDCODE_VAL;
        else begin
            case (tap_state)
                TAP_CAP_DR:   if (ir_reg == IR_IDCODE) idcode_shift <= IDCODE_VAL;
                TAP_SHIFT_DR: if (ir_reg == IR_IDCODE) idcode_shift <= {jtag_tdi, idcode_shift[31:1]};
                default: ;
            endcase
        end
    end

    // ========================================================
    // DATA Register (68 bits, posedge jtag_tck)
    //
    // Capture (read back): {status, rdata, pc, core_state}
    // Shift in (command):  {cmd, addr, wdata, unused}
    // ========================================================
    
    // These are in clk_25 domain — read across clock domains
    // Safe because they're slow-changing and we capture in CAP_DR
    // which is well-separated in time from when they change
    reg [1:0]  bus_status;    // clk_25 domain
    reg [31:0] last_rdata;    // clk_25 domain
    reg        core_in_reset; // clk_25 domain
    reg        core_halted;   // clk_25 domain

    wire [1:0] cur_core_state = core_in_reset ? 2'b00 :
                                core_halted   ? 2'b01 : 2'b10;

    reg [67:0] data_shift;

    always @(posedge jtag_tck or negedge rst_n) begin
        if (!rst_n)
            data_shift <= 68'h0;
        else begin
            case (tap_state)
                TAP_CAP_DR: begin
                    if (ir_reg == IR_DATA)
                        data_shift <= {bus_status, last_rdata, debug_pc, cur_core_state};
                end
                TAP_SHIFT_DR: begin
                    if (ir_reg == IR_DATA)
                        data_shift <= {jtag_tdi, data_shift[67:1]};
                end
                default: ;
            endcase
        end
    end

    // ========================================================
    // Update-DR: latch command + toggle CDC signal
    // ========================================================
    reg        update_toggle;  // toggles on each Update-DR with IR=DATA
    reg [1:0]  cmd_reg;
    reg [31:0] addr_reg;
    reg [31:0] wdata_reg;

    always @(posedge jtag_tck or negedge rst_n) begin
        if (!rst_n) begin
            update_toggle <= 1'b0;
            cmd_reg       <= 2'b0;
            addr_reg      <= 32'h0;
            wdata_reg     <= 32'h0;
        end else begin
            if (tap_state == TAP_UPDATE_DR && ir_reg == IR_DATA) begin
                cmd_reg       <= data_shift[67:66];
                addr_reg      <= data_shift[65:34];
                wdata_reg     <= data_shift[33:2];
                update_toggle <= ~update_toggle;
            end
        end
    end

    // ========================================================
    // TDO (negedge jtag_tck)
    // ========================================================
    reg tdo_reg;
    always @(negedge jtag_tck or negedge rst_n) begin
        if (!rst_n)
            tdo_reg <= 1'b0;
        else begin
            case (tap_state)
                TAP_SHIFT_IR: tdo_reg <= ir_shift[0];
                TAP_SHIFT_DR: begin
                    case (ir_reg)
                        IR_BYPASS: tdo_reg <= bypass_reg;
                        IR_IDCODE: tdo_reg <= idcode_shift[0];
                        IR_DATA:   tdo_reg <= data_shift[0];
                        default:   tdo_reg <= 1'b0;
                    endcase
                end
                default: tdo_reg <= 1'b0;
            endcase
        end
    end
    assign jtag_tdo = tdo_reg;

    // ========================================================
    // CDC: toggle synchronizer (TCK → clk_25)
    //
    // update_toggle changes in TCK domain.
    // We sync it to clk_25 with 2 FFs, then detect edge.
    // By the time the edge is detected, cmd_reg/addr_reg/wdata_reg
    // have been stable for many clk_25 cycles (since TCK << clk_25).
    // ========================================================
    reg sync1, sync2, sync3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync1 <= 1'b0;
            sync2 <= 1'b0;
            sync3 <= 1'b0;
        end else begin
            sync1 <= update_toggle;
            sync2 <= sync1;
            sync3 <= sync2;
        end
    end

    wire trigger = sync2 ^ sync3;  // pulse when toggle changes

    // ========================================================
    // Core Control (posedge clk_25)
    // ========================================================
    reg step_request;
    reg step_active;

    assign core_rst_n  = ~core_in_reset;
    assign core_clk_en = ~core_in_reset && (~core_halted || step_active);

    localparam CTRL_RESET   = 4'b0001;
    localparam CTRL_RELEASE = 4'b0010;
    localparam CTRL_STEP    = 4'b0100;
    localparam CTRL_HALT    = 4'b1000;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            core_in_reset <= 1'b1;
            core_halted   <= 1'b1;
            step_request  <= 1'b0;
            step_active   <= 1'b0;
        end else begin
            step_active <= 1'b0;

            if (step_request) begin
                step_active  <= 1'b1;
                step_request <= 1'b0;
            end

            if (trigger && cmd_reg == 2'b10) begin
                case (wdata_reg[3:0])
                    CTRL_RESET: begin
                        core_in_reset <= 1'b1;
                        core_halted   <= 1'b1;
                    end
                    CTRL_RELEASE: begin
                        core_in_reset <= 1'b0;
                        core_halted   <= 1'b0;
                    end
                    CTRL_STEP: begin
                        core_in_reset <= 1'b0;
                        core_halted   <= 1'b1;
                        step_request  <= 1'b1;
                    end
                    CTRL_HALT: begin
                        core_halted <= 1'b1;
                    end
                    default: ;
                endcase
            end
        end
    end

    // ========================================================
    // Bus Master FSM (posedge clk_25)
    // ========================================================
    localparam BUS_IDLE    = 2'd0;
    localparam BUS_REQUEST = 2'd1;
    localparam BUS_WAIT    = 2'd2;
    localparam BUS_DONE    = 2'd3;

    reg [1:0] bus_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bus_state  <= BUS_IDLE;
            bus_status <= 2'b00;
            last_rdata <= 32'h0;
            req_valid  <= 1'b0;
            req_addr   <= 32'h0;
            req_wdata  <= 32'h0;
            req_wmask  <= 4'h0;
            req_wen    <= 1'b0;
        end else begin
            case (bus_state)
                BUS_IDLE: begin
                    if (trigger && (cmd_reg == 2'b00 || cmd_reg == 2'b01)) begin
                        req_valid  <= 1'b1;
                        req_addr   <= addr_reg;
                        req_wen    <= cmd_reg[0];
                        req_wdata  <= wdata_reg;
                        req_wmask  <= 4'b1111;
                        bus_status <= 2'b10;
                        bus_state  <= BUS_REQUEST;
                    end
                end

                BUS_REQUEST: begin
                    if (req_ready)
                        bus_state <= BUS_WAIT;
                end

                BUS_WAIT: begin
                    if (resp_valid) begin
                        req_valid  <= 1'b0;
                        last_rdata <= resp_rdata;
                        bus_status <= 2'b01;
                        bus_state  <= BUS_DONE;
                    end
                end

                BUS_DONE: begin
                    // Keep status=01 (done) — cleared when new cmd starts
                    bus_state <= BUS_IDLE;
                end
            endcase
        end
    end

endmodule
