/*
 * tb_uart_rx.v
 *
 * Minimal self-checking testbench for uart_rx:
 * - Verifies normal reception (8N1, LSB-first)
 * - Verifies framing error when stop bit is 0
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

	wire [7:0] rx_data;
	wire rx_ready;
	wire rx_frame_error;

	uart_rx dut (
		.clk(clk),
		.reset(reset),
		.baud8_tick(baud8_tick),
		.rx(rx),
		.rx_data(rx_data),
		.rx_ready(rx_ready),
		.rx_frame_error(rx_frame_error)
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

	task automatic hold_line(input line_level, input integer ticks);
		integer i;
		begin
			rx = line_level;
			for (i = 0; i < ticks; i = i + 1)
				tick8();
		end
	endtask

	task automatic recv_expect(input [7:0] data_byte, input stop_ok);
		integer i;
		reg ready_seen;
		begin
			/* Start bit */
			hold_line(1'b0, 8);

			/* Data bits (LSB first) */
			for (i = 0; i < 8; i = i + 1)
				hold_line(data_byte[i], 8);

			/* Stop bit */
			hold_line(stop_ok ? 1'b1 : 1'b0, 8);

			/* Wait for rx_ready to assert (should happen shortly after stop) */
			ready_seen = 1'b0;
			begin : wait_ready
				for (i = 0; i < 200; i = i + 1) begin
					if (rx_ready) begin
						ready_seen = 1'b1;
						disable wait_ready;
					end
					tick8();
				end
			end
			if (!ready_seen)
				fail("Timed out waiting for rx_ready");

			if (rx_data !== data_byte)
				fail("rx_data mismatch");

			if (stop_ok) begin
				if (rx_frame_error !== 1'b0)
					fail("Unexpected rx_frame_error on good frame");
			end else begin
				if (rx_frame_error !== 1'b1)
					fail("Expected rx_frame_error on bad stop bit");
			end

			/* Return to idle for a bit */
			hold_line(1'b1, 16);
		end
	endtask

	initial begin
		clk = 1'b0;
		reset = 1'b1;
		baud8_tick = 1'b0;
		rx = 1'b1;

		/* Reset for a few cycles */
		repeat (5) @(posedge clk);
		reset = 1'b0;

		/* Provide some ticks with idle-high line */
		hold_line(1'b1, 32);

		recv_expect(8'hA5, 1'b1);
		recv_expect(8'h3C, 1'b0);

		$display("PASS");
		$finish(0);
	end
endmodule
