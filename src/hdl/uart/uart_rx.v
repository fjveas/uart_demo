/*
 * uart_rx.v
 * 2017/02/01 - Felipe Veas
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
	input rx_ack,
	output reg [7:0] rx_data,
	output reg rx_valid,
	/*
	 * rx_frame_error and rx_overrun are only meaningful while rx_valid is
	 * asserted; the consumer must sample them before issuing rx_ack.
	 *
	 * rx_frame_error: bad stop bit on the current byte.
	 * rx_overrun:     a new start bit arrived while the previous byte was
	 *                 waiting for rx_ack — that incoming frame will be lost.
	 */
	output reg rx_frame_error,
	output reg rx_overrun
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
	wire rx_ack_seen;
	wire start_attempt;

	/* Finite-state machine */
	reg [2:0] state, state_next;
	reg [2:0] bit_counter, bit_counter_next;
	reg [7:0] rx_data_next;
	reg frame_error, frame_error_next;
	reg overrun, overrun_next;
	reg rx_ack_pending;
	reg rx_bit_prev;
	reg start_pending;
	wire overrun_live;

	assign rx_ack_seen = rx_ack_pending | rx_ack;
	assign start_attempt = rx_bit_prev & ~rx_bit;
	assign overrun_live = overrun | start_pending;

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
		RX_READY: begin
			if (rx_ack_seen)
				state_next = RX_IDLE;
		end
		default:
			state_next = RX_IDLE;
		endcase
	end

	always @(*) begin
		bit_counter_next = bit_counter;
		spacing_counter_next = spacing_counter + 'd1;
		rx_valid = 1'b0;
		rx_frame_error = 1'b0;
		rx_overrun = 1'b0;
		rx_data_next = rx_data;
		frame_error_next = frame_error;
		overrun_next = overrun;

		case (state)
		RX_IDLE: begin
			bit_counter_next = 'd0;
			spacing_counter_next = 'd0;
			frame_error_next = 1'b0;
			overrun_next = 1'b0;
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
		RX_READY: begin
			/*
			 * Hold data/error valid until the consumer explicitly acknowledges
			 * the byte. rx_ack is captured in the clk domain, so a one-cycle
			 * pulse is enough even if it does not line up with baud8_tick.
			 */
			rx_valid = 1'b1;
			rx_frame_error = frame_error;
			rx_overrun = overrun_live;
			/*
			 * Latch overrun only on a new high-to-low transition while the
			 * previous byte is still waiting for rx_ack.
			 */
			overrun_next = overrun_live;
			if (rx_ack_seen)
				overrun_next = 1'b0;
		end
		endcase
	end

	always @(posedge clk) begin
		if (reset) begin
			spacing_counter <= 'd0;
			bit_counter <= 'd0;
			state <= RX_IDLE;
			rx_data <= 'd0;
			frame_error <= 1'b0;
			overrun <= 1'b0;
			rx_ack_pending <= 1'b0;
			rx_bit_prev <= 1'b1;
			start_pending <= 1'b0;
		end else begin
			rx_bit_prev <= rx_bit;

			if (rx_ack)
				rx_ack_pending <= 1'b1;

			if (state == RX_READY && start_attempt)
				start_pending <= 1'b1;

			if (baud8_tick) begin
				spacing_counter <= spacing_counter_next;
				bit_counter <= bit_counter_next;
				state <= state_next;
				rx_data <= rx_data_next;
				frame_error <= frame_error_next;
				overrun <= overrun_next;

				if (state == RX_READY && rx_ack_seen)
					rx_ack_pending <= 1'b0;

				if (state == RX_READY && rx_ack_seen)
					start_pending <= 1'b0;
				else if (state == RX_IDLE)
					start_pending <= 1'b0;
			end
		end
	end

endmodule
