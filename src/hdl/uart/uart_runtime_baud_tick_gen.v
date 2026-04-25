/*
 * uart_runtime_baud_tick_gen.v
 *
 * Runtime-selectable baud tick generator for UART.
 */

`timescale 1ns / 1ps

module uart_runtime_baud_tick_gen
#(
    parameter CLK_FREQUENCY = 100000000,
    parameter MIN_BAUD_RATE = 9600
)(
    input clk,
    input reset,
    input [2:0] cfg_baud_sel,
    input tx_busy,
    input rx_busy,
    input rx_valid,
    output baud_tick,
    output baud8_tick
);

    localparam BAUD_SEL_9600   = 3'd0;
    localparam BAUD_SEL_19200  = 3'd1;
    localparam BAUD_SEL_38400  = 3'd2;
    localparam BAUD_SEL_57600  = 3'd3;
    localparam BAUD_SEL_115200 = 3'd4;
    localparam BAUD_SEL_230400 = 3'd5;
    localparam BAUD_SEL_460800 = 3'd6;
    localparam BAUD_SEL_921600 = 3'd7;

    /*
     * ACC_WIDTH is sized for the slowest baud rate in the menu. If cfg_baud_sel
     * can reach a rate below MIN_BAUD_RATE, raise the parameter accordingly.
     */
    localparam ACC_WIDTH = $clog2(CLK_FREQUENCY / MIN_BAUD_RATE) + 8;

    reg [ACC_WIDTH:0] tx_acc;
    reg [ACC_WIDTH:0] rx_acc;
    reg [ACC_WIDTH:0] tx_increment_cfg;
    reg [ACC_WIDTH:0] rx_increment_cfg;
    reg [ACC_WIDTH:0] tx_increment_active;
    reg [ACC_WIDTH:0] rx_increment_active;

    function [ACC_WIDTH:0] baud_increment;
        input integer baud_rate;
        input integer oversampling;
        integer acc_width;
        integer shift_limiter;
        begin
            acc_width = $clog2(CLK_FREQUENCY / MIN_BAUD_RATE) + 8;
            shift_limiter = $clog2((baud_rate * oversampling) >> (31 - acc_width));
            /* Integer division yields 32 bits; the result is guaranteed to fit in
             * ACC_WIDTH+1 bits by construction. Verilog 2005 has no explicit
             * narrowing cast to express this, so the truncation warning is suppressed. */
            /* verilator lint_off WIDTHTRUNC */
            baud_increment =
                ((baud_rate * oversampling << (acc_width - shift_limiter)) +
                (CLK_FREQUENCY >> (shift_limiter + 1))) / (CLK_FREQUENCY >> shift_limiter);
            /* verilator lint_on WIDTHTRUNC */
        end
    endfunction

    assign baud_tick  = tx_acc[ACC_WIDTH];
    assign baud8_tick = rx_acc[ACC_WIDTH];

    always @(*) begin
        case (cfg_baud_sel)
        BAUD_SEL_9600: begin
            tx_increment_cfg = baud_increment(9600, 1);
            rx_increment_cfg = baud_increment(9600, 8);
        end
        BAUD_SEL_19200: begin
            tx_increment_cfg = baud_increment(19200, 1);
            rx_increment_cfg = baud_increment(19200, 8);
        end
        BAUD_SEL_38400: begin
            tx_increment_cfg = baud_increment(38400, 1);
            rx_increment_cfg = baud_increment(38400, 8);
        end
        BAUD_SEL_57600: begin
            tx_increment_cfg = baud_increment(57600, 1);
            rx_increment_cfg = baud_increment(57600, 8);
        end
        BAUD_SEL_115200: begin
            tx_increment_cfg = baud_increment(115200, 1);
            rx_increment_cfg = baud_increment(115200, 8);
        end
        BAUD_SEL_230400: begin
            tx_increment_cfg = baud_increment(230400, 1);
            rx_increment_cfg = baud_increment(230400, 8);
        end
        BAUD_SEL_460800: begin
            tx_increment_cfg = baud_increment(460800, 1);
            rx_increment_cfg = baud_increment(460800, 8);
        end
        BAUD_SEL_921600: begin
            tx_increment_cfg = baud_increment(921600, 1);
            rx_increment_cfg = baud_increment(921600, 8);
        end
        default: begin
            tx_increment_cfg = baud_increment(115200, 1);
            rx_increment_cfg = baud_increment(115200, 8);
        end
        endcase
    end

    always @(posedge clk) begin
        if (reset) begin
            tx_acc <= 'd0;
            rx_acc <= 'd0;
            tx_increment_active <= baud_increment(115200, 1);
            rx_increment_active <= baud_increment(115200, 8);
        end else begin
            if (!tx_busy)
                tx_increment_active <= tx_increment_cfg;

            /*
             * Refresh RX timing only while the receiver is fully idle. rx_busy
             * excludes all states except IDLE and READY; rx_valid marks READY.
             */
            if (!rx_busy && !rx_valid)
                rx_increment_active <= rx_increment_cfg;

            if (tx_busy)
                tx_acc <= tx_acc[ACC_WIDTH-1:0] + tx_increment_active;
            else
                tx_acc <= tx_increment_active;

            rx_acc <= rx_acc[ACC_WIDTH-1:0] + rx_increment_active;
        end
    end

endmodule

