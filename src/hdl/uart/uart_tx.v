/*
 * uart_tx.v
 * 2017/02/01 - Felipe Veas
 *
 * Asynchronous Transmitter.
 */

`timescale 1ns / 1ps

module uart_tx
#(
	parameter PARITY = 0  /* 0=none  1=even  2=odd */
)(
	input clk,
	input reset,
	input baud_tick,
	input tx_start,
	input [7:0] tx_data,
	output reg tx,
	output reg tx_busy
);

	localparam PARITY_EVEN = 1;
	localparam PARITY_ODD  = 2;

	localparam TX_IDLE   = 3'b000;
	localparam TX_START  = 3'b001;
	localparam TX_SEND   = 3'b010;
	localparam TX_STOP   = 3'b011;
	localparam TX_PARITY = 3'b100;

	reg [2:0] state, state_next;
	reg [2:0] counter, counter_next;
	reg [7:0] tx_data_reg;
	reg parity_acc, parity_acc_next;

	always @(posedge clk) begin
		if (reset)
			tx_data_reg <= 'd0;
		else if (state == TX_IDLE && tx_start)
			tx_data_reg <= tx_data;
	end

	always @(*) begin
		tx = 1'b1;
		tx_busy = 1'b1;
		state_next = state;
		counter_next = counter;
		parity_acc_next = parity_acc;

		case (state)
		TX_IDLE: begin
			tx_busy = 1'b0;
			parity_acc_next = 1'b0;
			if (tx_start)
				state_next = TX_START;
		end
		TX_START: begin
			tx = 1'b0;
			counter_next = 'd0;
			if (baud_tick)
				state_next = TX_SEND;
		end
		TX_SEND: begin
			tx = tx_data_reg[counter];
			if (baud_tick) begin
				parity_acc_next = parity_acc ^ tx_data_reg[counter];
				counter_next = counter + 'd1;
				if (counter == 'd7)
					state_next = (PARITY == PARITY_EVEN || PARITY == PARITY_ODD) ? TX_PARITY : TX_STOP;
			end
		end
		TX_PARITY: begin
			tx = parity_acc ^ (PARITY == PARITY_ODD ? 1'b1 : 1'b0);
			if (baud_tick)
				state_next = TX_STOP;
		end
		TX_STOP:
			if (baud_tick)
				state_next = TX_IDLE;
		default:
			state_next = TX_IDLE;
		endcase
	end

	always @(posedge clk) begin
		if (reset) begin
			state <= TX_IDLE;
			counter <= 'd0;
			parity_acc <= 1'b0;
		end else begin
			state <= state_next;
			counter <= counter_next;
			parity_acc <= parity_acc_next;
		end
	end

endmodule
