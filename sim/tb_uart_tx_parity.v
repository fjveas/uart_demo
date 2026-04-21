/*
 * tb_uart_tx_parity.v
 *
 * Parity-specific self-checking testbench for uart_tx.
 * Two DUT instances share the same stimulus; the only difference is the
 * compile-time PARITY parameter:
 *
 *   dut_even  PARITY=1  (even parity)
 *   dut_odd   PARITY=2  (odd  parity)
 *
 * For each test byte the expected parity bit is computed as:
 *   even  →  ^data_byte         (XOR of all 8 data bits)
 *   odd   →  ~^data_byte        (inverted XOR)
 *
 * Example (from repo root):
 *   verilator -Wall --binary sim/tb_uart_tx_parity.v src/hdl/uart/uart_tx.v
 */

`timescale 1ns / 1ps

module tb_uart_tx_parity;
	reg clk;
	reg reset;
	reg baud_tick;
	reg tx_start;
	reg [7:0] tx_data;
	reg [255:0] current_case;

	wire tx_even, tx_busy_even;
	wire tx_odd,  tx_busy_odd;

	uart_tx #(.PARITY(1)) dut_even (
		.clk(clk),
		.reset(reset),
		.baud_tick(baud_tick),
		.tx_start(tx_start),
		.tx_data(tx_data),
		.tx(tx_even),
		.tx_busy(tx_busy_even)
	);

	uart_tx #(.PARITY(2)) dut_odd (
		.clk(clk),
		.reset(reset),
		.baud_tick(baud_tick),
		.tx_start(tx_start),
		.tx_data(tx_data),
		.tx(tx_odd),
		.tx_busy(tx_busy_odd)
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

	/*
	 * Drive data_byte through both DUTs simultaneously and verify the full
	 * frame: start bit, 8 data bits (LSB-first), parity bit, stop bit, and
	 * tx_busy deassertion.  The parity bit is computed from data_byte alone —
	 * no magic constants in the test.
	 */
	task automatic send_and_check_parity(input [7:0] data_byte);
		integer i;
		reg exp_even_par;
		reg exp_odd_par;
		begin
			exp_even_par = ^data_byte;    /* XOR reduction: 0 if even number of 1s */
			exp_odd_par  = ~^data_byte;   /* inverted XOR */

			tx_data  = data_byte;
			tx_start = 1'b1;
			@(posedge clk);
			tx_start = 1'b0;
			@(posedge clk);

			/* Start bit — both DUTs must drive the line low. */
			if (tx_even !== 1'b0) fail("even: start bit not low");
			if (tx_odd  !== 1'b0) fail("odd:  start bit not low");
			if (tx_busy_even !== 1'b1) fail("even: tx_busy not set during start");
			if (tx_busy_odd  !== 1'b1) fail("odd:  tx_busy not set during start");

			tick1(); /* → TX_SEND, bit index 0 */

			/* Eight data bits, LSB first. */
			for (i = 0; i < 8; i = i + 1) begin
				if (tx_even !== data_byte[i]) fail("even: data bit mismatch");
				if (tx_odd  !== data_byte[i]) fail("odd:  data bit mismatch");
				tick1();
			end

			/*
			 * Parity bit.  For even parity the TX must output 1 if the number
			 * of 1s in data_byte is odd (to make the total even), and 0
			 * otherwise.  Odd parity is the complement.
			 */
			if (tx_even !== exp_even_par) fail("even: wrong parity bit");
			if (tx_odd  !== exp_odd_par)  fail("odd:  wrong parity bit");
			tick1();

			/* Stop bit — both DUTs must return to idle-high. */
			if (tx_even !== 1'b1) fail("even: stop bit not high");
			if (tx_odd  !== 1'b1) fail("odd:  stop bit not high");
			tick1();

			/* Both DUTs must return to IDLE. */
			if (tx_busy_even !== 1'b0) fail("even: tx_busy did not deassert");
			if (tx_busy_odd  !== 1'b0) fail("odd:  tx_busy did not deassert");
		end
	endtask

	initial begin
		$dumpfile("build/tb_uart_tx_parity/tb_uart_tx_parity.fst");
		$dumpvars(0, tb_uart_tx_parity);

		$display("[tb_uart_tx_parity]");

		clk       = 1'b0;
		reset     = 1'b1;
		baud_tick = 1'b0;
		tx_start  = 1'b0;
		tx_data   = 8'h00;
		current_case = "";

		repeat (5) @(posedge clk);
		reset = 1'b0;
		repeat (2) @(posedge clk);

		/*
		 * 8'hA5 = 1010_0101 — four 1s (even count).
		 * Expected: even parity bit = 0, odd parity bit = 1.
		 * Exercises the case where the even-parity bit must be 0.
		 */
		set_case("tx parity A5");
		send_and_check_parity(8'hA5);

		/*
		 * 8'h07 = 0000_0111 — three 1s (odd count).
		 * Expected: even parity bit = 1, odd parity bit = 0.
		 * Exercises the opposite polarity: even-parity bit must be 1.
		 */
		set_case("tx parity 07");
		send_and_check_parity(8'h07);

		/*
		 * 8'h00 — no 1s; parity accumulator must start clean on every new
		 * frame (not carry over from the previous one).
		 * Expected: even parity bit = 0, odd parity bit = 1.
		 */
		set_case("tx parity 00");
		send_and_check_parity(8'h00);

		/*
		 * 8'hFF = 1111_1111 — eight 1s (even count).
		 * Expected: even parity bit = 0, odd parity bit = 1.
		 * Verifies accumulator handles a run of all-ones correctly.
		 */
		set_case("tx parity FF");
		send_and_check_parity(8'hFF);

		$display("PASS");
		$finish(0);
	end
endmodule
