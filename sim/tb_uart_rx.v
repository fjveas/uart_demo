/*
 * tb_uart_rx.v
 *
 * Minimal self-checking testbench for uart_rx:
 * - Verifies normal reception (8N1, LSB-first)
 * - Verifies framing error when stop bit is 0
 * - Verifies rx_overrun when a start bit arrives before rx_ack
 *
 * Example (from repo root):
 *   verilator -Wall --binary sim/tb_uart_rx.v \
 *     src/hdl/uart/uart_rx.v src/hdl/uart/data_sync.v
 */

`timescale 1ns / 1ps

module tb_uart_rx;
	reg clk;
	reg reset;
	reg baud8_tick;
	reg rx; /* UART idle-high */
	reg rx_ack;

	wire [7:0] rx_data;
	wire rx_valid;
	wire rx_frame_error;
	wire rx_overrun;

	uart_rx dut (
		.clk(clk),
		.reset(reset),
		.baud8_tick(baud8_tick),
		.rx(rx),
		.rx_ack(rx_ack),
		.rx_data(rx_data),
		.rx_valid(rx_valid),
		.rx_frame_error(rx_frame_error),
		.rx_overrun(rx_overrun)
	);

	always #5 clk = ~clk;

	task automatic fail(input [1023:0] msg);
		begin
			$display("FAIL: %0s", msg);
			$finish(1);
		end
	endtask

	/*
	 * Pulse baud8_tick such that it is high on a rising edge of clk.
	 * uart_rx advances only on clock edges where baud8_tick=1.
	 */
	task automatic tick8;
		begin
			baud8_tick = 1'b1;
			@(posedge clk);
			baud8_tick = 1'b0;
			@(posedge clk);
		end
	endtask

	task automatic pulse_ack_clk;
		begin
			@(negedge clk);
			rx_ack = 1'b1;
			@(negedge clk);
			rx_ack = 1'b0;
		end
	endtask

	task automatic hold_line(input line_level, input integer ticks);
		integer i;
		begin
			rx = line_level;
			for (i = 0; i < ticks; i = i + 1)
				tick8();
		end
	endtask

	task automatic recv_expect(input [7:0] data_byte, input stop_ok, input integer idle_ticks_after);
		integer i;
		reg valid_seen;
		begin
			/* Start bit */
			hold_line(1'b0, 8);

			/* Data bits (LSB first) */
			for (i = 0; i < 8; i = i + 1)
				hold_line(data_byte[i], 8);

			/* Stop bit */
			hold_line(stop_ok ? 1'b1 : 1'b0, 8);

			/* Wait for rx_valid to assert (should happen shortly after stop). */
			valid_seen = 1'b0;
			begin : wait_valid
				for (i = 0; i < 200; i = i + 1) begin
					if (rx_valid) begin
						valid_seen = 1'b1;
						disable wait_valid;
					end
					tick8();
				end
			end
			if (!valid_seen)
				fail("Timed out waiting for rx_valid");

			if (rx_data !== data_byte)
				fail("rx_data mismatch");

			if (stop_ok) begin
				if (rx_frame_error !== 1'b0)
					fail("Unexpected rx_frame_error on good frame");
			end else begin
				if (rx_frame_error !== 1'b1)
					fail("Expected rx_frame_error on bad stop bit");
			end

			if (rx_overrun !== 1'b0)
				fail("Unexpected rx_overrun on normal frame");

			/*
			 * rx_valid should stay asserted until the consumer acknowledges
			 * the received byte.
			 */
			repeat (4) begin
				if (rx_valid !== 1'b1)
					fail("rx_valid deasserted before rx_ack");
				tick8();
			end

			pulse_ack_clk();
			begin : wait_valid_clear
				for (i = 0; i < 32; i = i + 1) begin
					if (rx_valid !== 1'b0)
						tick8();
					else
						disable wait_valid_clear;
				end
				fail("rx_valid did not clear after rx_ack");
			end
			if (rx_frame_error !== 1'b0)
				fail("rx_frame_error did not clear after rx_ack");
			if (rx_overrun !== 1'b0)
				fail("rx_overrun did not clear after rx_ack");

			/* Return to idle for a bit (or start the next frame immediately) */
			if (idle_ticks_after > 0)
				hold_line(1'b1, idle_ticks_after);
		end
	endtask

	/* Short low glitch should be filtered and must not produce rx_valid. */
	task automatic start_glitch_expect_no_byte;
		integer i;
		begin
			/* Idle for a bit */
			hold_line(1'b1, 32);

			/* Glitch low for a couple of oversample ticks, then back high */
			hold_line(1'b0, 2);
			hold_line(1'b1, 64);

			/* Ensure no byte was reported */
			for (i = 0; i < 200; i = i + 1) begin
				if (rx_valid)
					fail("Unexpected rx_valid after start glitch");
				tick8();
			end
		end
	endtask

	/*
	 * Send a valid frame, hold rx_ack, drive a start bit on the line, then
	 * verify rx_overrun latches and clears after rx_ack.
	 */
	task automatic overrun_test;
		integer i;
		reg valid_seen;
		reg [7:0] test_byte;
		begin
			hold_line(1'b1, 8);
			test_byte = 8'hA5;

			/* Send a complete valid frame */
			hold_line(1'b0, 8);
			for (i = 0; i < 8; i = i + 1)
				hold_line(test_byte[i], 8);
			hold_line(1'b1, 8);

			/* Wait for rx_valid without acking */
			valid_seen = 1'b0;
			begin : wait_valid_ovr
				for (i = 0; i < 200; i = i + 1) begin
					if (rx_valid) begin
						valid_seen = 1'b1;
						disable wait_valid_ovr;
					end
					tick8();
				end
			end
			if (!valid_seen)
				fail("Overrun test: timed out waiting for rx_valid");
			if (rx_overrun !== 1'b0)
				fail("Overrun test: rx_overrun set before start bit");

			/* Drive a new start edge while still in RX_READY. */
			hold_line(1'b1, 4);
			hold_line(1'b0, 4);
			if (rx_overrun !== 1'b1)
				fail("Overrun test: rx_overrun not set after start edge in RX_READY");

			/* rx_valid should still be held */
			if (rx_valid !== 1'b1)
				fail("Overrun test: rx_valid dropped before rx_ack");

			/* Acknowledge — both flags must clear */
			pulse_ack_clk();
			begin : wait_overrun_clear
				for (i = 0; i < 32; i = i + 1) begin
					if (rx_valid !== 1'b0)
						tick8();
					else
						disable wait_overrun_clear;
				end
				fail("Overrun test: rx_valid did not clear after rx_ack");
			end
			if (rx_overrun !== 1'b0)
				fail("Overrun test: rx_overrun did not clear after rx_ack");

			hold_line(1'b1, 16);
		end
	endtask

	initial begin
		$dumpfile("build/tb_uart_rx/tb_uart_rx.fst");
		$dumpvars(0, tb_uart_rx);

		$display("[tb_uart_rx]");

		clk = 1'b0;
		reset = 1'b1;
		baud8_tick = 1'b0;
		rx = 1'b1;
		rx_ack = 1'b0;

		/* Reset for a few cycles */
		repeat (5) @(posedge clk);
		reset = 1'b0;

		/* Settle the line high before any frames arrive. */
		hold_line(1'b1, 32);

		/* A brief low glitch (< half a bit period) must be filtered out by
		 * data_sync hysteresis and must not produce rx_valid. */
		$display("  start glitch filter");
		start_glitch_expect_no_byte();

		/* Normal 8N1 frame: verifies data integrity, rx_valid handshake,
		 * and that rx_frame_error stays clear on a good stop bit. */
		$display("  recv_expect(8'hA5, good stop)");
		recv_expect(8'hA5, 1'b1, 16);

		/* Frame with a bad stop bit (stop=0): verifies rx_frame_error
		 * asserts alongside rx_valid and clears after rx_ack. */
		$display("  recv_expect(8'h3C, bad stop)");
		recv_expect(8'h3C, 1'b0, 16);

		/* Two good frames sent with no idle gap between them: verifies the
		 * FSM returns to RX_IDLE promptly after rx_ack and catches the next
		 * start bit without missing it. */
		$display("  back-to-back recv_expect(8'h12, 8'h34)");
		recv_expect(8'h12, 1'b1, 0);
		recv_expect(8'h34, 1'b1, 16);

		/* A new start edge arrives while the previous byte sits unacknowledged
		 * in RX_READY: verifies rx_overrun latches, rx_valid stays held, and
		 * both flags clear together on rx_ack. */
		$display("  overrun test");
		overrun_test();

		$display("PASS");
		$finish(0);
	end
endmodule
