/*
 * tb_uart_top_parity.v
 *
 * Integration testbench for uart_top with parity enabled:
 * - Validates TX parity generation through uart_top for even and odd parity
 * - Validates RX parity error reporting through uart_top for even and odd parity
 *
 * Example (from repo root):
 *   verilator -Wall --binary sim/tb_uart_top_parity.v \
 *     src/hdl/uart/uart_top.v src/hdl/uart/uart_tx.v src/hdl/uart/uart_rx.v \
 *     src/hdl/uart/uart_baud_tick_gen.v src/hdl/uart/data_sync.v
 */

`timescale 1ns / 1ps

module tb_uart_top_parity;
	localparam CLK_FREQUENCY = 100000000;
	localparam BAUD_RATE = 115200;
	localparam integer CYCLES_PER_BIT_APPROX = (CLK_FREQUENCY / BAUD_RATE);

	reg clk;
	reg reset;

	reg rx_in;
	reg rx_ack;

	reg tx_start;
	reg [7:0] tx_data;

	wire [7:0] rx_data_even;
	wire rx_valid_even;
	wire rx_frame_error_even;
	wire rx_parity_error_even;
	wire rx_overrun_even;
	wire tx_even;
	wire tx_busy_even;

	wire [7:0] rx_data_odd;
	wire rx_valid_odd;
	wire rx_frame_error_odd;
	wire rx_parity_error_odd;
	wire rx_overrun_odd;
	wire tx_odd;
	wire tx_busy_odd;

	uart_top #(
		.CLK_FREQUENCY(CLK_FREQUENCY),
		.BAUD_RATE(BAUD_RATE),
		.PARITY(1)
	) dut_even (
		.clk(clk),
		.reset(reset),
		.rx(rx_in),
		.rx_data(rx_data_even),
		.rx_valid(rx_valid_even),
		.rx_frame_error(rx_frame_error_even),
		.rx_parity_error(rx_parity_error_even),
		.rx_overrun(rx_overrun_even),
		.rx_ack(rx_ack),
		.tx(tx_even),
		.tx_start(tx_start),
		.tx_data(tx_data),
		.tx_busy(tx_busy_even)
	);

	uart_top #(
		.CLK_FREQUENCY(CLK_FREQUENCY),
		.BAUD_RATE(BAUD_RATE),
		.PARITY(2)
	) dut_odd (
		.clk(clk),
		.reset(reset),
		.rx(rx_in),
		.rx_data(rx_data_odd),
		.rx_valid(rx_valid_odd),
		.rx_frame_error(rx_frame_error_odd),
		.rx_parity_error(rx_parity_error_odd),
		.rx_overrun(rx_overrun_odd),
		.rx_ack(rx_ack),
		.tx(tx_odd),
		.tx_start(tx_start),
		.tx_data(tx_data),
		.tx_busy(tx_busy_odd)
	);

	always #5 clk = ~clk;

	task automatic fail(input [1023:0] msg);
		begin
			$display("FAIL: %0s", msg);
			$finish(1);
		end
	endtask

	task automatic pulse_tx_start;
		begin
			@(negedge clk);
			tx_start = 1'b1;
			@(negedge clk);
			tx_start = 1'b0;
		end
	endtask

	task automatic pulse_rx_ack;
		begin
			@(negedge clk);
			rx_ack = 1'b1;
			@(negedge clk);
			rx_ack = 1'b0;
		end
	endtask

	task automatic wait_baud_event;
		begin
			while (!dut_even.baud_tick)
				@(posedge clk);
			@(posedge clk);
		end
	endtask

	task automatic wait_rx_valid_both(
		input integer timeout_cycles,
		output reg [7:0] rx_data_seen_even,
		output reg [7:0] rx_data_seen_odd
	);
		integer i;
		reg valid_seen;
		begin
			valid_seen = 1'b0;
			rx_data_seen_even = 8'h00;
			rx_data_seen_odd = 8'h00;
			begin : wait_loop
				for (i = 0; i < timeout_cycles; i = i + 1) begin
					#1ps;
					if (rx_valid_even && rx_valid_odd) begin
						valid_seen = 1'b1;
						rx_data_seen_even = rx_data_even;
						rx_data_seen_odd = rx_data_odd;
						disable wait_loop;
					end
					@(posedge clk);
				end
			end
			if (!valid_seen)
				fail("Timed out waiting for rx_valid on both parity DUTs");
		end
	endtask

	task automatic tx_send_and_check_parity(input [7:0] data_byte);
		integer i;
		reg start_seen;
		integer half_bit_cycles;
		reg exp_even_par;
		reg exp_odd_par;
		begin
			exp_even_par = ^data_byte;
			exp_odd_par = ~^data_byte;
			tx_data = data_byte;
			pulse_tx_start();

			start_seen = 1'b0;
			begin : wait_start
				for (i = 0; i < (2 * CYCLES_PER_BIT_APPROX); i = i + 1) begin
					#1ps;
					if (tx_even == 1'b0 && tx_odd == 1'b0) begin
						start_seen = 1'b1;
						disable wait_start;
					end
					@(posedge clk);
				end
			end
			if (!start_seen)
				fail("TX parity start bit not observed");

			half_bit_cycles = (CYCLES_PER_BIT_APPROX / 2);

			wait_baud_event();
			for (i = 0; i < 8; i = i + 1) begin
				repeat (half_bit_cycles) @(posedge clk);
				#1ps;
				if (tx_even !== data_byte[i])
					fail("even uart_top: TX data bit mismatch");
				if (tx_odd !== data_byte[i])
					fail("odd uart_top: TX data bit mismatch");
				wait_baud_event();
			end

			repeat (half_bit_cycles) @(posedge clk);
			#1ps;
			if (tx_even !== exp_even_par)
				fail("even uart_top: wrong parity bit");
			if (tx_odd !== exp_odd_par)
				fail("odd uart_top: wrong parity bit");
			wait_baud_event();

			repeat (half_bit_cycles) @(posedge clk);
			#1ps;
			if (tx_even !== 1'b1)
				fail("even uart_top: stop bit not high");
			if (tx_odd !== 1'b1)
				fail("odd uart_top: stop bit not high");
			wait_baud_event();
			#1ps;
			if (tx_busy_even !== 1'b0)
				fail("even uart_top: tx_busy did not clear");
			if (tx_busy_odd !== 1'b0)
				fail("odd uart_top: tx_busy did not clear");
		end
	endtask

	task automatic rx_send_and_expect_parity(
		input [7:0] data_byte,
		input parity_bit,
		input expect_even_error,
		input expect_odd_error
	);
		integer i;
		integer ack_cycles;
		reg [7:0] rx_data_seen_even;
		reg [7:0] rx_data_seen_odd;
		begin
			rx_in = 1'b0;
			repeat (CYCLES_PER_BIT_APPROX) @(posedge clk);

			for (i = 0; i < 8; i = i + 1) begin
				rx_in = data_byte[i];
				repeat (CYCLES_PER_BIT_APPROX) @(posedge clk);
			end

			rx_in = parity_bit;
			repeat (CYCLES_PER_BIT_APPROX) @(posedge clk);

			rx_in = 1'b1;
			wait_rx_valid_both(48 * CYCLES_PER_BIT_APPROX, rx_data_seen_even, rx_data_seen_odd);
			repeat (CYCLES_PER_BIT_APPROX / 2) @(posedge clk);

			if (rx_data_seen_even !== data_byte)
				fail("even uart_top: RX data mismatch");
			if (rx_data_seen_odd !== data_byte)
				fail("odd uart_top: RX data mismatch");

			if (rx_frame_error_even !== 1'b0)
				fail("even uart_top: unexpected rx_frame_error");
			if (rx_frame_error_odd !== 1'b0)
				fail("odd uart_top: unexpected rx_frame_error");
			if (rx_overrun_even !== 1'b0)
				fail("even uart_top: unexpected rx_overrun");
			if (rx_overrun_odd !== 1'b0)
				fail("odd uart_top: unexpected rx_overrun");

			if (expect_even_error) begin
				if (rx_parity_error_even !== 1'b1)
					fail("even uart_top: expected rx_parity_error");
			end else begin
				if (rx_parity_error_even !== 1'b0)
					fail("even uart_top: unexpected rx_parity_error");
			end

			if (expect_odd_error) begin
				if (rx_parity_error_odd !== 1'b1)
					fail("odd uart_top: expected rx_parity_error");
			end else begin
				if (rx_parity_error_odd !== 1'b0)
					fail("odd uart_top: unexpected rx_parity_error");
			end

			repeat (4) begin
				#1ps;
				if (rx_valid_even !== 1'b1)
					fail("even uart_top: rx_valid deasserted before rx_ack");
				if (rx_valid_odd !== 1'b1)
					fail("odd uart_top: rx_valid deasserted before rx_ack");
				@(posedge clk);
			end

			pulse_rx_ack();
			begin : wait_clear
				for (ack_cycles = 0; ack_cycles < (2 * CYCLES_PER_BIT_APPROX); ack_cycles = ack_cycles + 1) begin
					@(posedge clk);
					#1ps;
					if (rx_valid_even === 1'b0 && rx_valid_odd === 1'b0)
						disable wait_clear;
				end
				fail("uart_top parity: rx_valid did not clear after rx_ack");
			end

			if (rx_parity_error_even !== 1'b0)
				fail("even uart_top: rx_parity_error did not clear after rx_ack");
			if (rx_parity_error_odd !== 1'b0)
				fail("odd uart_top: rx_parity_error did not clear after rx_ack");

			rx_in = 1'b1;
			repeat (2 * CYCLES_PER_BIT_APPROX) @(posedge clk);
		end
	endtask

	initial begin
		$dumpfile("build/tb_uart_top_parity/tb_uart_top_parity.fst");
		$dumpvars(0, tb_uart_top_parity);

		$display("[tb_uart_top_parity]");

		clk = 1'b0;
		reset = 1'b1;
		rx_in = 1'b1;
		rx_ack = 1'b0;
		tx_start = 1'b0;
		tx_data = 8'h00;

		repeat (10) @(posedge clk);
		reset = 1'b0;

		$display("  TX parity: tx_send_and_check_parity(8'hA5)");
		tx_send_and_check_parity(8'hA5);
		$display("  TX parity: tx_send_and_check_parity(8'h07)");
		tx_send_and_check_parity(8'h07);

		$display("  RX parity: 8'hA5 parity=0 [even: ok, odd: error]");
		rx_send_and_expect_parity(8'hA5, 1'b0, 1'b0, 1'b1);
		$display("  RX parity: 8'hA5 parity=1 [even: error, odd: ok]");
		rx_send_and_expect_parity(8'hA5, 1'b1, 1'b1, 1'b0);

		$display("PASS");
		$finish(0);
	end
endmodule
