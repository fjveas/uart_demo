/*
 * uart_rx.v
 * 2017/02/01 - Felipe Veas <felipe.veasv at usm.cl>
 *
 * Asynchronous Receiver.
 */

`timescale 1ns / 1ps

module uart_rx
(
	input clk,
	input reset,
	input baud8_tick,
	input rx,
	output reg [7:0] rx_data,
	output reg rx_ready,
	/*
	 * Asserted alongside rx_ready to indicate a framing error (bad stop bit).
	 * This is a pulse-like signal at the "byte ready" boundary: it stays
	 * asserted while the internal FSM is in RX_READY (until the next baud8_tick).
	 */
	output reg rx_frame_error
);

	localparam RX_IDLE  = 'b000;
	localparam RX_START = 'b001;
	localparam RX_RECV  = 'b010;
	localparam RX_STOP  = 'b011;
	localparam RX_READY = 'b100;

	/* Clock synchronized rx input */
	wire rx_bit;
	data_sync rx_sync_inst (
		.clk(clk),
		.reset(reset),
		.in(rx),
		.stable_out(rx_bit)
	);

	/* Bit spacing counter (oversampling) */
	reg [2:0] spacing_counter, spacing_counter_next;
	wire next_bit;
	assign next_bit = (spacing_counter == 'd4);

	/* Finite-state machine */
	reg [2:0] state, state_next;
	reg [2:0] bit_counter, bit_counter_next;
	reg [7:0] rx_data_next;
	reg frame_error, frame_error_next;

	always @(*) begin
		state_next = state;

		case (state)
		RX_IDLE:
			if (rx_bit == 1'b0)
				state_next = RX_START;
		RX_START: begin
			if (next_bit) begin
				if (rx_bit == 1'b0) // Start bit must be a 0
					state_next = RX_RECV;
				else
					state_next = RX_IDLE;
			end
		end
		RX_RECV:
			if (next_bit && bit_counter == 'd7)
				state_next = RX_STOP;
		RX_STOP:
			if (next_bit)
				state_next = RX_READY;
		RX_READY:
			state_next = RX_IDLE;
		default:
			state_next = RX_IDLE;
		endcase
	end

	always @(*) begin
		bit_counter_next = bit_counter;
		spacing_counter_next = spacing_counter + 'd1;
		rx_ready = 1'b0;
		rx_frame_error = 1'b0;
		rx_data_next = rx_data;
		frame_error_next = frame_error;

		case (state)
		RX_IDLE: begin
			bit_counter_next = 'd0;
			spacing_counter_next = 'd0;
			frame_error_next = 1'b0;
		end
		RX_RECV: begin
			if (next_bit) begin
				bit_counter_next = bit_counter + 'd1;
				rx_data_next = {rx_bit, rx_data[7:1]};
			end
		end
		RX_STOP: begin
			if (next_bit) begin
				/* Stop bit must be a 1, otherwise this is a framing error. */
				if (rx_bit == 1'b0)
					frame_error_next = 1'b1;
			end
		end
		RX_READY:
			rx_ready = 1'b1;
		endcase

		/* Provide the framing result at the same time as rx_ready. */
		if (state == RX_READY)
			rx_frame_error = frame_error;
	end

	always @(posedge clk) begin
		if (reset) begin
			spacing_counter <= 'd0;
			bit_counter <= 'd0;
			state <= RX_IDLE;
			rx_data <= 'd0;
			frame_error <= 1'b0;
		end else if (baud8_tick) begin
			spacing_counter <= spacing_counter_next;
			bit_counter <= bit_counter_next;
			state <= state_next;
			rx_data <= rx_data_next;
			frame_error <= frame_error_next;
		end
	end

endmodule
