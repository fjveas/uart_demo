/*
 * tb_uart_rx_parity.v
 *
 * Parity-specific self-checking testbench for uart_rx.
 * Two DUT instances share the same stimulus; the only difference is the
 * compile-time PARITY parameter:
 *
 *   dut_even  PARITY=1  (even parity)
 *   dut_odd   PARITY=2  (odd  parity)
 *
 * Because both DUTs see the same rx waveform, a single driven parity bit
 * exercises both the "correct parity" and "wrong parity" paths in one pass:
 *
 *   data XOR=0, drive parity=0  -> dut_even: no error   dut_odd: error
 *   data XOR=0, drive parity=1  -> dut_even: error      dut_odd: no error
 *   data XOR=1, drive parity=1  -> dut_even: no error   dut_odd: error
 *   data XOR=1, drive parity=0  -> dut_even: error      dut_odd: no error
 *
 * Example (from repo root):
 *   verilator -Wall --binary sim/tb_uart_rx_parity.v \
 *     src/hdl/uart/uart_rx.v src/hdl/uart/data_sync.v
 */

`timescale 1ns / 1ps

module tb_uart_rx_parity;
    reg clk;
    reg reset;
    reg baud8_tick;
    reg rx;
    reg rx_ack;
    reg [255:0] current_case;

    wire [7:0] rx_data_even;
    wire rx_valid_even;
    wire rx_frame_error_even;
    wire rx_parity_error_even;
    wire rx_overrun_even;

    wire [7:0] rx_data_odd;
    wire rx_valid_odd;
    wire rx_frame_error_odd;
    wire rx_parity_error_odd;
    wire rx_overrun_odd;

    uart_rx #(.PARITY(1)) dut_even (
        .clk(clk),
        .reset(reset),
        .baud8_tick(baud8_tick),
        .rx(rx),
        .rx_ack(rx_ack),
        .rx_data(rx_data_even),
        .rx_valid(rx_valid_even),
        .rx_frame_error(rx_frame_error_even),
        .rx_parity_error(rx_parity_error_even),
        .rx_overrun(rx_overrun_even)
    );

    uart_rx #(.PARITY(2)) dut_odd (
        .clk(clk),
        .reset(reset),
        .baud8_tick(baud8_tick),
        .rx(rx),
        .rx_ack(rx_ack),
        .rx_data(rx_data_odd),
        .rx_valid(rx_valid_odd),
        .rx_frame_error(rx_frame_error_odd),
        .rx_parity_error(rx_parity_error_odd),
        .rx_overrun(rx_overrun_odd)
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

    task automatic pulse_ack_clk;
        begin
            @(negedge clk);
            rx_ack = 1'b1;
            @(negedge clk);
            rx_ack = 1'b0;
        end
    endtask

    /*
     * Drive a complete 11-bit frame (start + 8 data + parity + stop) onto
     * the shared rx line and verify rx_parity_error on both DUTs according to
     * the caller-supplied expectations.  Also checks that:
     *   - rx_data is correct on both DUTs regardless of parity outcome
     *   - rx_frame_error is clear (stop bit is always valid here)
     *   - rx_valid stays asserted until rx_ack
     *   - rx_parity_error clears after rx_ack
     */
    task automatic recv_parity_expect(
        input [7:0] data_byte,
        input       parity_bit,
        input       expect_even_error,
        input       expect_odd_error
    );
        integer i;
        reg valid_seen;
        reg cleared;
        begin
            /* Start bit */
            hold_line(1'b0, 8);

            /* Data bits, LSB first */
            for (i = 0; i < 8; i = i + 1)
                hold_line(data_byte[i], 8);

            /* Parity bit */
            hold_line(parity_bit, 8);

            /* Stop bit */
            hold_line(1'b1, 8);

            /*
             * Both DUTs receive identical input so they assert rx_valid on the
             * same tick.  Wait for both together.
             */
            valid_seen = 1'b0;
            begin : wait_valid_par
                for (i = 0; i < 200; i = i + 1) begin
                    if (rx_valid_even & rx_valid_odd) begin
                        valid_seen = 1'b1;
                        disable wait_valid_par;
                    end
                    tick8();
                end
            end
            if (!valid_seen)
                fail("Timed out waiting for rx_valid on both DUTs");

            /* Data must be correct regardless of parity outcome. */
            if (rx_data_even !== data_byte) fail("even: rx_data mismatch");
            if (rx_data_odd  !== data_byte) fail("odd:  rx_data mismatch");

            /* Frame error must not be set -- we always send a valid stop bit. */
            if (rx_frame_error_even !== 1'b0) fail("even: unexpected rx_frame_error");
            if (rx_frame_error_odd  !== 1'b0) fail("odd:  unexpected rx_frame_error");

            /* No spurious overrun. */
            if (rx_overrun_even !== 1'b0) fail("even: unexpected rx_overrun");
            if (rx_overrun_odd  !== 1'b0) fail("odd:  unexpected rx_overrun");

            /* Parity error flag per-DUT as specified by the caller. */
            if (expect_even_error) begin
                if (rx_parity_error_even !== 1'b1)
                    fail("even: rx_parity_error not set when expected");
            end else begin
                if (rx_parity_error_even !== 1'b0)
                    fail("even: rx_parity_error set unexpectedly");
            end

            if (expect_odd_error) begin
                if (rx_parity_error_odd !== 1'b1)
                    fail("odd:  rx_parity_error not set when expected");
            end else begin
                if (rx_parity_error_odd !== 1'b0)
                    fail("odd:  rx_parity_error set unexpectedly");
            end

            /*
             * rx_valid must remain asserted until the consumer explicitly
             * acknowledges the byte.
             */
            repeat (4) begin
                if (rx_valid_even !== 1'b1)
                    fail("even: rx_valid deasserted before rx_ack");
                if (rx_valid_odd !== 1'b1)
                    fail("odd:  rx_valid deasserted before rx_ack");
                tick8();
            end

            /* Acknowledge and wait for both DUTs to return to IDLE. */
            pulse_ack_clk();
            cleared = 1'b0;
            begin : wait_clear_par
                for (i = 0; i < 32; i = i + 1) begin
                    if (rx_valid_even === 1'b0 && rx_valid_odd === 1'b0) begin
                        cleared = 1'b1;
                        disable wait_clear_par;
                    end
                    tick8();
                end
            end
            if (!cleared)
                fail("rx_valid did not clear after rx_ack");

            /* Both error flags must clear on return to IDLE. */
            if (rx_parity_error_even !== 1'b0)
                fail("even: rx_parity_error did not clear after rx_ack");
            if (rx_parity_error_odd !== 1'b0)
                fail("odd:  rx_parity_error did not clear after rx_ack");

            /* Settle back to idle before the next frame. */
            hold_line(1'b1, 16);
        end
    endtask

    initial begin
        $dumpfile("build/tb_uart_rx_parity/tb_uart_rx_parity.fst");
        $dumpvars(0, tb_uart_rx_parity);

        $display("[tb_uart_rx_parity]");

        clk        = 1'b0;
        reset      = 1'b1;
        baud8_tick = 1'b0;
        rx         = 1'b1;
        rx_ack     = 1'b0;
        current_case = "";

        repeat (5) @(posedge clk);
        reset = 1'b0;
        hold_line(1'b1, 32);

        /*
         * 8'hA5 = 1010_0101 -- four 1s, XOR=0.
         * Drive parity bit = 0 (matches even parity, violates odd parity).
         * Expected: dut_even no error, dut_odd error.
         */
        set_case("rx parity A5 bit0");
        recv_parity_expect(8'hA5, 1'b0, 1'b0, 1'b1);

        /*
         * 8'hA5, parity bit = 1 (violates even, matches odd).
         * Expected: dut_even error, dut_odd no error.
         */
        set_case("rx parity A5 bit1");
        recv_parity_expect(8'hA5, 1'b1, 1'b1, 1'b0);

        /*
         * 8'h07 = 0000_0111 -- three 1s, XOR=1.
         * Drive parity bit = 1 (matches even parity, violates odd parity).
         * Expected: dut_even no error, dut_odd error.
         */
        set_case("rx parity 07 bit1");
        recv_parity_expect(8'h07, 1'b1, 1'b0, 1'b1);

        /*
         * 8'h07, parity bit = 0 (violates even, matches odd).
         * Expected: dut_even error, dut_odd no error.
         */
        set_case("rx parity 07 bit0");
        recv_parity_expect(8'h07, 1'b0, 1'b1, 1'b0);

        /*
         * 8'h00 -- no 1s, XOR=0.  Parity accumulator must start clean each
         * frame; drive parity=0 to verify the even case at the boundary.
         * Expected: dut_even no error, dut_odd error.
         */
        set_case("rx parity 00 bit0");
        recv_parity_expect(8'h00, 1'b0, 1'b0, 1'b1);

        /*
         * 8'hFF -- eight 1s, XOR=0.  Verifies the accumulator handles a
         * sustained run of all-ones without overflow.
         * Drive parity=0 (matches even).
         * Expected: dut_even no error, dut_odd error.
         */
        set_case("rx parity FF bit0");
        recv_parity_expect(8'hFF, 1'b0, 1'b0, 1'b1);

        $display("PASS");
        $finish(0);
    end
endmodule
