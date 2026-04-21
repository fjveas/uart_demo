/*
 * tb_uart_tx.v
 *
 * Minimal self-checking testbench for uart_tx:
 * - Verifies start bit, 8 data bits (LSB-first), and stop bit.
 *
 * Example (from repo root):
 *   verilator -Wall --binary sim/tb_uart_tx.v src/hdl/uart/uart_tx.v
 */

`timescale 1ns / 1ps

module tb_uart_tx;
	reg clk;
	reg reset;
	reg baud_tick;
	reg tx_start;
	reg [7:0] tx_data;

	wire tx;
	wire tx_busy;

	uart_tx dut (
		.clk(clk),
		.reset(reset),
		.baud_tick(baud_tick),
		.tx_start(tx_start),
		.tx_data(tx_data),
		.tx(tx),
		.tx_busy(tx_busy)
	);

	always #5 clk = ~clk;

	task automatic fail(input [1023:0] msg);
		begin
			$display("FAIL: %0s", msg);
			$finish(1);
		end
	endtask

	task automatic tick1;
		begin
			baud_tick = 1'b1;
			@(posedge clk);
			baud_tick = 1'b0;
			@(posedge clk);
		end
	endtask

	task automatic send_and_check(input [7:0] data_byte);
		integer i;
		begin
			/* Kick the transmitter for one cycle */
			tx_data = data_byte;
			tx_start = 1'b1;
			@(posedge clk);
			tx_start = 1'b0;
			@(posedge clk);

			/* Start bit should be active now */
			if (tx !== 1'b0)
				fail("Start bit not driven low");

			/* Advance into TX_SEND and check each data bit */
			tick1();
			for (i = 0; i < 8; i = i + 1) begin
				if (tx !== data_byte[i])
					fail("Data bit mismatch");
				tick1();
			end

			/* Stop bit */
			if (tx !== 1'b1)
				fail("Stop bit not driven high");

			/* Return to IDLE on next tick */
			tick1();
			if (tx_busy !== 1'b0)
				fail("tx_busy did not deassert in IDLE");
		end
	endtask

	initial begin
		clk = 1'b0;
		reset = 1'b1;
		baud_tick = 1'b0;
		tx_start = 1'b0;
		tx_data = 8'h00;

		repeat (5) @(posedge clk);
		reset = 1'b0;

		/* Idle line should be high */
		repeat (5) @(posedge clk);
		if (tx !== 1'b1)
			fail("TX not idle-high");

		send_and_check(8'hA5);
		send_and_check(8'h00);
		send_and_check(8'hFF);

		$display("PASS");
		$finish(0);
	end
endmodule
