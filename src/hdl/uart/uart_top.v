/*
 * uart_top.v
 * 2017/02/01 - Felipe Veas
 *
 * Universal Asynchronous Receiver/Transmitter (top-level wrapper).
 */

`timescale 1ns / 1ps

module uart_top
#(
	parameter CLK_FREQUENCY = 100000000,
	parameter BAUD_RATE     = 115200,
	parameter PARITY        = 0  /* PARITY_NONE=0  PARITY_EVEN=1  PARITY_ODD=2 */
)(
	input clk,
	input reset,
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
	wire rx_valid_pre;
	wire rx_frame_error_pre;
	wire rx_parity_error_pre;
	wire rx_overrun_pre;

	uart_baud_tick_gen #(
		.CLK_FREQUENCY(CLK_FREQUENCY),
		.BAUD_RATE(BAUD_RATE),
		.OVERSAMPLING(8)
	) baud8_tick_blk (
		.clk(clk),
		.reset(reset),
		.enable(1'b1),
		.tick(baud8_tick)
	);

	uart_rx #(
		.PARITY(PARITY)
	) uart_rx_blk (
		.clk(clk),
		.reset(reset),
		.baud8_tick(baud8_tick),
		.rx(rx),
		.rx_ack(rx_ack),
		.rx_data(rx_data),
		.rx_valid(rx_valid_pre),
		.rx_frame_error(rx_frame_error_pre),
		.rx_parity_error(rx_parity_error_pre),
		.rx_overrun(rx_overrun_pre)
	);

	/*
	 * rx_valid, rx_frame_error, rx_parity_error, and rx_overrun remain
	 * asserted until rx_ack acknowledges the received byte.
	 */
	assign rx_valid        = rx_valid_pre;
	assign rx_frame_error  = rx_frame_error_pre;
	assign rx_parity_error = rx_parity_error_pre;
	assign rx_overrun      = rx_overrun_pre;

	uart_baud_tick_gen #(
		.CLK_FREQUENCY(CLK_FREQUENCY),
		.BAUD_RATE(BAUD_RATE),
		.OVERSAMPLING(1)
	) baud_tick_blk (
		.clk(clk),
		.reset(reset),
		.enable(tx_busy),
		.tick(baud_tick)
	);

	uart_tx #(
		.PARITY(PARITY)
	) uart_tx_blk (
		.clk(clk),
		.reset(reset),
		.baud_tick(baud_tick),
		.tx(tx),
		.tx_start(tx_start),
		.tx_data(tx_data),
		.tx_busy(tx_busy)
	);

endmodule
