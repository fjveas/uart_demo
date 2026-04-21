/*
 * uart_top.v
 * 2017/02/01 - Felipe Veas <felipe.veasv at usm.cl>
 *
 * Universal Asynchronous Receiver/Transmitter (top-level wrapper).
 */

`timescale 1ns / 1ps

module uart_top
#(
	parameter CLK_FREQUENCY = 100000000,
	parameter BAUD_RATE = 115200
)(
	input clk,
	input reset,
	input rx,
	output [7:0] rx_data,
	output reg rx_ready,
	output reg rx_frame_error,
	output tx,
	input tx_start,
	input [7:0] tx_data,
	output tx_busy
);

	wire baud8_tick;
	wire baud_tick;

	reg rx_ready_sync;
	wire rx_ready_pre;
	wire rx_frame_error_pre;

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

	uart_rx uart_rx_blk (
		.clk(clk),
		.reset(reset),
		.baud8_tick(baud8_tick),
		.rx(rx),
		.rx_data(rx_data),
		.rx_ready(rx_ready_pre),
		.rx_frame_error(rx_frame_error_pre)
	);

	always @(posedge clk) begin
		if (reset) begin
			rx_ready_sync <= 1'b0;
			rx_ready <= 1'b0;
			rx_frame_error <= 1'b0;
		end else begin
			rx_ready_sync <= rx_ready_pre;
			/* rx_ready and rx_frame_error are single-cycle wrapper pulses. */
			rx_ready <= ~rx_ready_sync & rx_ready_pre;

			/*
			 * rx_frame_error is meaningful only when a new byte becomes ready.
			 * Pulse it in sync with rx_ready.
			 */
			if (~rx_ready_sync & rx_ready_pre)
				rx_frame_error <= rx_frame_error_pre;
			else
				rx_frame_error <= 1'b0;
		end
	end

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

	uart_tx uart_tx_blk (
		.clk(clk),
		.reset(reset),
		.baud_tick(baud_tick),
		.tx(tx),
		.tx_start(tx_start),
		.tx_data(tx_data),
		.tx_busy(tx_busy)
	);

endmodule
