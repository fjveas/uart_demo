/*
 * uart_top_runtime.v
 *
 * Runtime-configurable UART top-level wrapper.
 */

`timescale 1ns / 1ps

module uart_top_runtime
#(
    parameter CLK_FREQUENCY = 100000000,
    parameter MIN_BAUD_RATE = 9600
)(
    input clk,
    input reset,
    input [2:0] cfg_baud_sel,
    input [1:0] cfg_parity,
    input rx,
    output [7:0] rx_data,
    output rx_valid,
    output rx_frame_error,
    output rx_parity_error,
    output rx_overrun,
    input rx_ack,
    output tx,
    input tx_start,
    input [7:0] tx_data,
    output tx_busy
);

    wire baud8_tick;
    wire baud_tick;
    wire rx_busy;
    wire rx_valid_pre;
    wire rx_frame_error_pre;
    wire rx_parity_error_pre;
    wire rx_overrun_pre;

    uart_runtime_baud_tick_gen #(
        .CLK_FREQUENCY(CLK_FREQUENCY),
        .MIN_BAUD_RATE(MIN_BAUD_RATE)
    ) baud_tick_gen_blk (
        .clk(clk),
        .reset(reset),
        .cfg_baud_sel(cfg_baud_sel),
        .tx_busy(tx_busy),
        .rx_busy(rx_busy),
        .rx_valid(rx_valid_pre),
        .baud_tick(baud_tick),
        .baud8_tick(baud8_tick)
    );

    uart_rx_core uart_rx_blk (
        .clk(clk),
        .reset(reset),
        .baud8_tick(baud8_tick),
        .cfg_parity(cfg_parity),
        .rx(rx),
        .rx_ack(rx_ack),
        .rx_data(rx_data),
        .rx_valid(rx_valid_pre),
        .rx_frame_error(rx_frame_error_pre),
        .rx_parity_error(rx_parity_error_pre),
        .rx_overrun(rx_overrun_pre),
        .rx_busy(rx_busy)
    );

    assign rx_valid        = rx_valid_pre;
    assign rx_frame_error  = rx_frame_error_pre;
    assign rx_parity_error = rx_parity_error_pre;
    assign rx_overrun      = rx_overrun_pre;

    uart_tx_core uart_tx_blk (
        .clk(clk),
        .reset(reset),
        .baud_tick(baud_tick),
        .cfg_parity(cfg_parity),
        .tx(tx),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_busy(tx_busy)
    );

endmodule
