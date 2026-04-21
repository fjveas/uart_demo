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
	reg [255:0] current_case;

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
			$display("FAIL [%0s]: %0s", current_case, msg);
			$finish(1);
		end
	endtask

	task automatic set_case(input [255:0] name);
		begin
			current_case = name;
			$display("  case: %0s", name);
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

			if (tx_busy !== 1'b1)
				fail("tx_busy not asserted during frame");

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

	/*
	 * Verify that data is latched on start and doesn't change mid-frame,
	 * and that tx_start pulses during TX busy are ignored.
	 */
	task automatic send_with_noise_and_check(input [7:0] data_byte, input [7:0] noisy_byte);
		integer i;
		begin
			tx_data = data_byte;
			tx_start = 1'b1;
			@(posedge clk);
			tx_start = 1'b0;
			@(posedge clk);

			/* Immediately change the input bus; TX should keep the original byte. */
			tx_data = noisy_byte;

			/* Start bit */
			if (tx !== 1'b0)
				fail("Start bit not driven low (noise test)");

			/* Enter TX_SEND */
			tick1();

			/* Mid-frame, pulse tx_start with another byte; should be ignored. */
			tx_data = ~data_byte;
			tx_start = 1'b1;
			@(posedge clk);
			tx_start = 1'b0;
			@(posedge clk);

			for (i = 0; i < 8; i = i + 1) begin
				if (tx !== data_byte[i])
					fail("Latched data changed mid-frame");
				tick1();
			end

			/* Stop bit then return to IDLE */
			if (tx !== 1'b1)
				fail("Stop bit not driven high (noise test)");
			tick1();
			if (tx_busy !== 1'b0)
				fail("tx_busy did not deassert in IDLE (noise test)");

			/* Ensure we didn't accidentally start a second frame. */
			repeat (10) @(posedge clk);
			if (tx !== 1'b1)
				fail("Unexpected second frame after ignored tx_start");
		end
	endtask

	initial begin
		$dumpfile("build/tb_uart_tx/tb_uart_tx.fst");
		$dumpvars(0, tb_uart_tx);

		$display("[tb_uart_tx]");

		clk = 1'b0;
		reset = 1'b1;
		baud_tick = 1'b0;
		tx_start = 1'b0;
		tx_data = 8'h00;
		current_case = "";

		repeat (5) @(posedge clk);
		reset = 1'b0;

		/* UART lines are idle-high; verify the TX line sits high before any
		 * frame is sent. */
		repeat (5) @(posedge clk);
		set_case("idle high");
		if (tx !== 1'b1)
			fail("TX not idle-high");

		/* Alternating-bit pattern: exercises both polarities on every bit
		 * position across start, data, and stop. */
		set_case("tx A5");
		send_and_check(8'hA5);

		/* All-zeros: verifies the transmitter holds the line low across all
		 * eight data bits without drifting to idle. */
		set_case("tx 00");
		send_and_check(8'h00);

		/* All-ones: verifies the transmitter holds the line high across all
		 * eight data bits (indistinguishable from idle, so framing is
		 * critical here). */
		set_case("tx FF");
		send_and_check(8'hFF);

		/* tx_data is changed immediately after tx_start and again mid-frame;
		 * verifies the transmitter latches the byte on the start edge and
		 * ignores all subsequent changes until the frame completes. */
		set_case("tx latch under noise");
		send_with_noise_and_check(8'h55, 8'hAA);

		$display("PASS");
		$finish(0);
	end
endmodule
