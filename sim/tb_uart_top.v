/*
 * tb_uart_top.v
 *
 * Integration testbench for uart_top:
 * - Validates TX path using the internal baud tick generator
 * - Validates RX path using the internal 8x oversampling tick generator
 * - Checks rx_frame_error on a bad stop bit
 * - Checks rx_overrun when a start bit arrives before rx_ack
 *
 * Example (from repo root):
 *   verilator -Wall --binary sim/tb_uart_top.v \
 *     src/hdl/uart/uart_top.v src/hdl/uart/uart_tx.v src/hdl/uart/uart_rx.v \
 *     src/hdl/uart/uart_baud_tick_gen.v src/hdl/uart/data_sync.v
 */

`timescale 1ns / 1ps

module tb_uart_top;
	/* Match the project's default parameters */
	localparam CLK_FREQUENCY = 100000000;
	localparam BAUD_RATE = 115200;

	/* Conservative timeout helper for long-running waits. */
	localparam integer CYCLES_PER_BIT_APPROX = (CLK_FREQUENCY / BAUD_RATE);

	reg clk;
	reg reset;

	reg rx_in;
	reg rx_ack;

	reg tx_start;
	reg [7:0] tx_data;

	wire [7:0] rx_data;
	wire rx_valid;
	wire rx_frame_error;
	wire rx_overrun;
	wire tx;
	wire tx_busy;

	uart_top #(
		.CLK_FREQUENCY(CLK_FREQUENCY),
		.BAUD_RATE(BAUD_RATE)
	) dut (
		.clk(clk),
		.reset(reset),
		.rx(rx_in),
		.rx_data(rx_data),
		.rx_valid(rx_valid),
		.rx_frame_error(rx_frame_error),
		.rx_overrun(rx_overrun),
		.rx_ack(rx_ack),
		.tx(tx),
		.tx_start(tx_start),
		.tx_data(tx_data),
		.tx_busy(tx_busy)
	);

	always #5 clk = ~clk; /* 100 MHz */

	task automatic fail(input [1023:0] msg);
		begin
			$display("FAIL: %0s", msg);
			$finish(1);
		end
	endtask

	task automatic pulse_tx_start;
		begin
			/*
			 * Hold tx_start high across a rising edge without racing the DUT's
			 * posedge-triggered logic. Deassert on a falling edge.
			 */
			@(negedge clk);
			tx_start = 1'b1;
			@(negedge clk);
			tx_start = 1'b0;
		end
	endtask

	/*
	 * The baud generators are synchronous but `tick` is combinational off the
	 * accumulator reg. The UART blocks "consume" tick on the following clk edge,
	 * so we wait for tick to become 1, then wait one more clk to let the DUT
	 * advance.
	 */
	task automatic wait_baud_event;
		begin
			while (!dut.baud_tick)
				@(posedge clk);
			@(posedge clk);
		end
	endtask

	task automatic wait_rx_valid(
		input integer timeout_cycles,
		output reg [7:0] rx_data_seen,
		output reg rx_frame_error_seen
	);
		integer i;
		reg valid_seen;
		begin
			valid_seen = 1'b0;
			rx_data_seen = 8'h00;
			rx_frame_error_seen = 1'b0;
			begin : wait_loop
				for (i = 0; i < timeout_cycles; i = i + 1) begin
					#1ps; /* observe rx_valid after NBA updates */
					if (rx_valid) begin
						valid_seen = 1'b1;
						rx_data_seen = rx_data;
						rx_frame_error_seen = rx_frame_error;
						disable wait_loop;
					end
					@(posedge clk);
				end
			end
			if (!valid_seen)
				fail("Timed out waiting for rx_valid");
		end
	endtask

	task automatic tx_send_and_check(input [7:0] data_byte);
		integer i;
		reg start_seen;
		integer half_bit_cycles;
		begin
			tx_data = data_byte;
			pulse_tx_start();

			/* Wait for start bit (TX line low). */
			start_seen = 1'b0;
			begin : wait_start
				for (i = 0; i < (2 * CYCLES_PER_BIT_APPROX); i = i + 1) begin
					#1ps; /* observe outputs after NBA updates */
					if (tx == 1'b0) begin
						start_seen = 1'b1;
						disable wait_start;
					end
					@(posedge clk);
				end
			end
			if (!start_seen)
				fail("TX start bit not observed");

			/*
			 * Data bits: sample mid-bit to avoid boundary ambiguity.
			 * (At each baud_tick, uart_tx updates its internal counter/state.)
			 */
			half_bit_cycles = (CYCLES_PER_BIT_APPROX / 2);

			/* End start bit, enter data bit 0. */
			wait_baud_event();
			for (i = 0; i < 8; i = i + 1) begin
				repeat (half_bit_cycles) @(posedge clk);
				#1ps;
				if (tx !== data_byte[i])
					fail("TX data bit mismatch");

				/* Advance to next bit boundary (bit i+1, or stop after bit 7). */
				wait_baud_event();
			end

			/* Stop bit: we are now in TX_STOP */
			repeat (half_bit_cycles) @(posedge clk);
			#1ps;
			if (tx !== 1'b1)
				fail("TX stop bit not high");

			/* Return to idle on next baud tick event (end of stop bit) */
			wait_baud_event();
			#1ps;
			if (tx_busy !== 1'b0)
				fail("TX did not return to IDLE");
			if (tx !== 1'b1)
				fail("TX not idle-high after frame");
		end
	endtask

	task automatic rx_send_and_expect(input [7:0] data_byte, input stop_ok);
		integer baud_ticks_seen;
		integer ack_cycles;
		reg [7:0] rx_data_seen;
		reg rx_frame_error_seen;
		begin
			/*
			 * Drive RX as a real UART waveform using approximate bit timing.
			 * This avoids depending on internal baud8_tick phase in simulation.
			 */

			/* Start bit */
			rx_in = 1'b0;
			repeat (CYCLES_PER_BIT_APPROX) @(posedge clk);

			/* Data bits (LSB first) */
			for (baud_ticks_seen = 0; baud_ticks_seen < 8; baud_ticks_seen = baud_ticks_seen + 1) begin
				rx_in = data_byte[baud_ticks_seen];
				repeat (CYCLES_PER_BIT_APPROX) @(posedge clk);
			end

			/* Stop bit */
			rx_in = stop_ok ? 1'b1 : 1'b0;
			/* rx_valid asserts once the stop bit has been checked. */
			wait_rx_valid(40 * CYCLES_PER_BIT_APPROX, rx_data_seen, rx_frame_error_seen);
			/*
			 * Return line to idle before further waits. A bad stop bit leaves
			 * rx_in=0; if left low into RX_READY it would be mistaken for a
			 * new start bit and falsely assert rx_overrun.
			 */
			rx_in = 1'b1;
			repeat (CYCLES_PER_BIT_APPROX / 2) @(posedge clk);
			if (rx_data_seen !== data_byte)
				fail("RX data mismatch");

			if (stop_ok) begin
				if (rx_frame_error_seen !== 1'b0)
					fail("Unexpected rx_frame_error on good RX frame");
			end else begin
				if (rx_frame_error_seen !== 1'b1)
					fail("Expected rx_frame_error on bad stop bit");
			end

			#1ps;
			if (rx_overrun !== 1'b0)
				fail("Unexpected rx_overrun on normal RX frame");

			/*
			 * rx_valid should remain asserted until acknowledged, then clear
			 * on the next clock.
			 */
			repeat (4) begin
				#1ps;
				if (rx_valid !== 1'b1)
					fail("rx_valid deasserted before rx_ack");
				@(posedge clk);
			end

			@(negedge clk);
			rx_ack = 1'b1;
			begin : wait_ack_clear
				for (ack_cycles = 0; ack_cycles < (2 * CYCLES_PER_BIT_APPROX); ack_cycles = ack_cycles + 1) begin
					@(posedge clk);
					#1ps;
					if (rx_valid === 1'b0)
						disable wait_ack_clear;
				end
				fail("rx_valid did not clear after rx_ack");
			end
			if (rx_frame_error !== 1'b0)
				fail("rx_frame_error did not clear after rx_ack");
			if (rx_overrun !== 1'b0)
				fail("rx_overrun did not clear after rx_ack");
			@(negedge clk);
			rx_ack = 1'b0;

			/* Idle */
			rx_in = 1'b1;
			repeat (2 * CYCLES_PER_BIT_APPROX) @(posedge clk);
		end
	endtask

	/*
	 * Send a valid frame, hold rx_ack, drive a start bit, then verify
	 * rx_overrun latches and clears after rx_ack.
	 */
	task automatic rx_overrun_test;
		integer i;
		integer ack_cycles;
		reg [7:0] rx_data_seen;
		reg rx_frame_error_seen;
		reg [7:0] test_byte;
		begin
			test_byte = 8'hA5;
			/* Send a complete valid frame */
			rx_in = 1'b0;
			repeat (CYCLES_PER_BIT_APPROX) @(posedge clk);
			for (i = 0; i < 8; i = i + 1) begin
				rx_in = test_byte[i];
				repeat (CYCLES_PER_BIT_APPROX) @(posedge clk);
			end
			rx_in = 1'b1;

			/* Wait for rx_valid without acking */
			wait_rx_valid(40 * CYCLES_PER_BIT_APPROX, rx_data_seen, rx_frame_error_seen);
			#1ps;
			if (rx_data_seen !== test_byte)
				fail("Overrun test: rx_data mismatch");
			if (rx_frame_error_seen !== 1'b0)
				fail("Overrun test: unexpected rx_frame_error");
			if (rx_overrun !== 1'b0)
				fail("Overrun test: rx_overrun set before start bit");

			/* Drive a start bit while still in RX_READY */
			rx_in = 1'b0;
			repeat (CYCLES_PER_BIT_APPROX) @(posedge clk);
			#1ps;
			if (rx_overrun !== 1'b1)
				fail("Overrun test: rx_overrun not set after start bit in RX_READY");
			if (rx_valid !== 1'b1)
				fail("Overrun test: rx_valid dropped before rx_ack");

			/* Acknowledge — all flags must clear */
			rx_in = 1'b1;
			@(negedge clk);
			rx_ack = 1'b1;
			begin : wait_ack_clear_ovr
				for (ack_cycles = 0; ack_cycles < (2 * CYCLES_PER_BIT_APPROX); ack_cycles = ack_cycles + 1) begin
					@(posedge clk);
					#1ps;
					if (rx_valid === 1'b0)
						disable wait_ack_clear_ovr;
				end
				fail("Overrun test: rx_valid did not clear after rx_ack");
			end
			if (rx_overrun !== 1'b0)
				fail("Overrun test: rx_overrun did not clear after rx_ack");
			@(negedge clk);
			rx_ack = 1'b0;

			repeat (2 * CYCLES_PER_BIT_APPROX) @(posedge clk);
		end
	endtask

	initial begin
		clk = 1'b0;
		reset = 1'b1;
		rx_in = 1'b1;
		rx_ack = 1'b0;
		tx_start = 1'b0;
		tx_data = 8'h00;

		repeat (10) @(posedge clk);
		reset = 1'b0;

		/* TX path (with internal baud tick generation) */
		tx_send_and_check(8'hA5);
		tx_send_and_check(8'h00);
		tx_send_and_check(8'hFF);

		/* RX path (with internal oversampling tick generation) */
		rx_send_and_expect(8'h3C, 1'b1);
		rx_send_and_expect(8'h5A, 1'b0);

		rx_overrun_test();

		$display("PASS");
		$finish(0);
	end
endmodule
