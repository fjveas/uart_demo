/*
 * tb_uart_top_runtime.v
 *
 * Integration testbench for uart_top_runtime:
 * - Baud rate selection at 9600 and 921600
 * - Parity and baud latching during active TX/RX frames
 * - Frame-structure transitions: NONE <-> EVEN parity
 * - Parity error, frame error, and overrun detection
 * - Baud rate update gated by rx_valid (byte pending acknowledgement)
 */

`timescale 1ns / 1ps

module tb_uart_top_runtime;
    localparam CLK_FREQUENCY = 100000000;
    localparam BAUD_SEL_9600   = 3'd0;
    localparam BAUD_SEL_115200 = 3'd4;
    localparam BAUD_SEL_921600 = 3'd7;
    localparam PARITY_NONE = 2'd0;
    localparam PARITY_EVEN = 2'd1;
    localparam PARITY_ODD  = 2'd2;

    reg clk;
    reg reset;
    reg [2:0] cfg_baud_sel;
    reg [1:0] cfg_parity;
    reg rx_in;
    reg rx_ack;
    reg tx_start;
    reg [7:0] tx_data;
    reg [255:0] current_case;

    wire [7:0] rx_data;
    wire rx_valid;
    wire rx_frame_error;
    wire rx_parity_error;
    wire rx_overrun;
    wire tx;
    wire tx_busy;

    uart_top_runtime #(
        .CLK_FREQUENCY(CLK_FREQUENCY)
    ) dut (
        .clk(clk),
        .reset(reset),
        .cfg_baud_sel(cfg_baud_sel),
        .cfg_parity(cfg_parity),
        .rx(rx_in),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_frame_error(rx_frame_error),
        .rx_parity_error(rx_parity_error),
        .rx_overrun(rx_overrun),
        .rx_ack(rx_ack),
        .tx(tx),
        .tx_start(tx_start),
        .tx_data(tx_data),
        .tx_busy(tx_busy)
    );

    always #5 clk = ~clk;

    function automatic integer cycles_per_bit_from_sel(input [2:0] baud_sel);
        begin
            case (baud_sel)
            BAUD_SEL_9600:   cycles_per_bit_from_sel = (CLK_FREQUENCY / 9600);
            BAUD_SEL_115200: cycles_per_bit_from_sel = (CLK_FREQUENCY / 115200);
            BAUD_SEL_921600: cycles_per_bit_from_sel = (CLK_FREQUENCY / 921600);
            default:         cycles_per_bit_from_sel = (CLK_FREQUENCY / 115200);
            endcase
        end
    endfunction

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

    task automatic wait_tx_start_low(input integer timeout_cycles);
        integer i;
        reg start_seen;
        begin
            start_seen = 1'b0;
            begin : wait_tx_low
                for (i = 0; i < timeout_cycles; i = i + 1) begin
                    @(posedge clk);
                    #1ps;
                    if (tx == 1'b0) begin
                        start_seen = 1'b1;
                        disable wait_tx_low;
                    end
                end
            end
            if (!start_seen)
                fail("Timed out waiting for TX start bit");
        end
    endtask

    task automatic wait_rx_valid_capture(input integer timeout_cycles);
        integer i;
        reg valid_seen;
        begin
            valid_seen = 1'b0;
            begin : wait_rx_valid
                for (i = 0; i < timeout_cycles; i = i + 1) begin
                    @(posedge clk);
                    #1ps;
                    if (rx_valid) begin
                        valid_seen = 1'b1;
                        disable wait_rx_valid;
                    end
                end
            end
            if (!valid_seen)
                fail("Timed out waiting for rx_valid");
        end
    endtask

    /*
     * TX: drive a full frame, sample each bit at mid-bit, and optionally
     * change cfg_parity or cfg_baud_sel mid-frame to verify the latch.
     */
    task automatic tx_send_and_check_cfg(
        input [7:0] data_byte,
        input integer cycles_per_bit,
        input [1:0] parity_mode,
        input bit change_parity_mid_frame,
        input [1:0] parity_after_change,
        input bit change_baud_mid_frame,
        input [2:0] baud_sel_after_change
    );
        integer i;
        integer clear_cycles;
        integer half_bit_cycles;
        reg expected_parity_bit;
        begin
            tx_data = data_byte;
            pulse_tx_start();
            wait_tx_start_low(2 * cycles_per_bit);

            half_bit_cycles = (cycles_per_bit / 2);
            expected_parity_bit = ^data_byte;
            if (parity_mode == PARITY_ODD)
                expected_parity_bit = ~expected_parity_bit;

            repeat (cycles_per_bit) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                repeat (half_bit_cycles) @(posedge clk);
                #1ps;
                if (tx !== data_byte[i])
                    fail("TX data bit mismatch");

                if (change_parity_mid_frame && i == 3)
                    cfg_parity = parity_after_change;
                if (change_baud_mid_frame && i == 3)
                    cfg_baud_sel = baud_sel_after_change;

                repeat (cycles_per_bit - half_bit_cycles) @(posedge clk);
            end

            if (parity_mode == PARITY_NONE) begin
                repeat (half_bit_cycles) @(posedge clk);
                #1ps;
                if (tx !== 1'b1)
                    fail("TX stop bit not high in no-parity mode");
                repeat (cycles_per_bit - half_bit_cycles) @(posedge clk);
            end else begin
                repeat (half_bit_cycles) @(posedge clk);
                #1ps;
                if (tx !== expected_parity_bit)
                    fail("TX parity bit mismatch");
                repeat (cycles_per_bit - half_bit_cycles) @(posedge clk);

                repeat (half_bit_cycles) @(posedge clk);
                #1ps;
                if (tx !== 1'b1)
                    fail("TX stop bit not high after parity bit");
                repeat (cycles_per_bit - half_bit_cycles) @(posedge clk);
            end

            begin : wait_tx_clear
                for (clear_cycles = 0; clear_cycles < (2 * cycles_per_bit); clear_cycles = clear_cycles + 1) begin
                    @(posedge clk);
                    #1ps;
                    if (tx_busy === 1'b0)
                        disable wait_tx_clear;
                end
                fail("tx_busy did not clear");
            end
        end
    endtask

    /*
     * RX: drive a complete waveform with optional mid-frame config change,
     * then verify data and flags and acknowledge.
     */
    task automatic rx_send_and_expect_cfg(
        input [7:0] data_byte,
        input integer cycles_per_bit,
        input [1:0] parity_mode,
        input bit parity_bit,
        input bit expect_parity_error,
        input bit change_parity_mid_frame,
        input [1:0] parity_after_change,
        input bit change_baud_mid_frame,
        input [2:0] baud_sel_after_change
    );
        integer i;
        integer ack_cycles;
        begin
            rx_in = 1'b0;
            repeat (cycles_per_bit) @(posedge clk);

            for (i = 0; i < 8; i = i + 1) begin
                rx_in = data_byte[i];
                repeat (cycles_per_bit) @(posedge clk);
                if (change_parity_mid_frame && i == 3)
                    cfg_parity = parity_after_change;
                if (change_baud_mid_frame && i == 3)
                    cfg_baud_sel = baud_sel_after_change;
            end

            if (parity_mode != PARITY_NONE) begin
                rx_in = parity_bit;
                repeat (cycles_per_bit) @(posedge clk);
            end

            rx_in = 1'b1;
            wait_rx_valid_capture(64 * cycles_per_bit);

            if (rx_data !== data_byte)
                fail("RX data mismatch");
            if (rx_frame_error !== 1'b0)
                fail("Unexpected rx_frame_error");
            if (rx_overrun !== 1'b0)
                fail("Unexpected rx_overrun");
            if (rx_parity_error !== expect_parity_error)
                fail("Unexpected rx_parity_error value");

            pulse_rx_ack();
            begin : wait_rx_cfg_clear
                for (ack_cycles = 0; ack_cycles < (2 * cycles_per_bit); ack_cycles = ack_cycles + 1) begin
                    @(posedge clk);
                    #1ps;
                    if (rx_valid === 1'b0)
                        disable wait_rx_cfg_clear;
                end
                fail("rx_valid did not clear after rx_ack");
            end

            rx_in = 1'b1;
            repeat (2 * cycles_per_bit) @(posedge clk);
        end
    endtask

    /*
     * Drive a complete RX waveform without verifying or acknowledging.
     * Leaves rx_in at stop_bit on return; callers that drive stop=0 must
     * restore rx_in to 1 before waiting for rx_valid.
     */
    task automatic rx_send_frame(
        input [7:0]  data_byte,
        input integer cycles_per_bit,
        input [1:0]  parity_mode,
        input bit     parity_bit,
        input bit     stop_bit
    );
        integer i;
        begin
            rx_in = 1'b0;
            repeat (cycles_per_bit) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                rx_in = data_byte[i];
                repeat (cycles_per_bit) @(posedge clk);
            end
            if (parity_mode != PARITY_NONE) begin
                rx_in = parity_bit;
                repeat (cycles_per_bit) @(posedge clk);
            end
            rx_in = stop_bit;
        end
    endtask

    /*
     * Wait for rx_valid, verify all flags, acknowledge, wait for clear.
     * Drives rx_in high on entry so a low stop_bit does not look like a
     * new start bit while the task waits.
     */
    task automatic rx_check_and_ack(
        input [7:0]  data_byte,
        input integer timeout_cycles,
        input bit     expect_frame_error,
        input bit     expect_parity_error,
        input bit     expect_overrun
    );
        integer ack_cycles;
        begin
            wait_rx_valid_capture(timeout_cycles);
            /* Drive line high only after rx_valid — not before — so that a
             * bad stop bit (stop=0) is still low when the DUT samples it. */
            rx_in = 1'b1;
            #1ps;
            if (rx_data !== data_byte)
                fail("rx_data mismatch");
            if (rx_frame_error !== expect_frame_error)
                fail("rx_frame_error has unexpected value");
            if (rx_parity_error !== expect_parity_error)
                fail("rx_parity_error has unexpected value");
            if (rx_overrun !== expect_overrun)
                fail("rx_overrun has unexpected value");

            pulse_rx_ack();
            begin : wait_simple_ack_clear
                for (ack_cycles = 0; ack_cycles < timeout_cycles; ack_cycles = ack_cycles + 1) begin
                    @(posedge clk);
                    #1ps;
                    if (rx_valid === 1'b0)
                        disable wait_simple_ack_clear;
                end
                fail("rx_valid did not clear after rx_ack");
            end

            rx_in = 1'b1;
            repeat (20) @(posedge clk);
        end
    endtask

    /*
     * Receive a frame, withhold rx_ack, assert a second start edge, and verify
     * rx_overrun latches while rx_valid stays held. Both flags must clear on ack.
     */
    task automatic rx_overrun_test(input integer cycles_per_bit);
        integer ack_cycles;
        begin
            rx_send_frame(8'hBB, cycles_per_bit, PARITY_NONE, 1'b0, 1'b1);
            rx_in = 1'b1;
            repeat (cycles_per_bit / 2) @(posedge clk);
            wait_rx_valid_capture(8 * cycles_per_bit);
            #1ps;
            if (rx_data !== 8'hBB)
                fail("Overrun: rx_data mismatch before second start edge");
            if (rx_overrun !== 1'b0)
                fail("Overrun: rx_overrun set before second start edge");

            /* Drive a new start edge while still in RX_READY. */
            rx_in = 1'b0;
            repeat (cycles_per_bit / 2) @(posedge clk);
            #1ps;
            if (rx_overrun !== 1'b1)
                fail("Overrun: rx_overrun not set after start edge in READY");
            if (rx_valid !== 1'b1)
                fail("Overrun: rx_valid dropped before rx_ack");

            rx_in = 1'b1;
            pulse_rx_ack();
            begin : wait_overrun_clear
                for (ack_cycles = 0; ack_cycles < (4 * cycles_per_bit); ack_cycles = ack_cycles + 1) begin
                    @(posedge clk);
                    #1ps;
                    if (rx_valid === 1'b0)
                        disable wait_overrun_clear;
                end
                fail("Overrun: rx_valid did not clear after rx_ack");
            end
            if (rx_overrun !== 1'b0)
                fail("Overrun: rx_overrun did not clear after rx_ack");

            rx_in = 1'b1;
            repeat (2 * cycles_per_bit) @(posedge clk);
        end
    endtask

    /*
     * Receive at 115200, withhold rx_ack, change baud to 9600, then ack.
     * The baud gen must not update rx_increment_active while rx_valid is
     * asserted (RX_READY state). Verified by receiving the next frame at
     * 9600 — incorrect accumulator phase from an early switch would corrupt it.
     */
    task automatic rx_baud_gate_test;
        integer ack_cycles;
        integer cpb_115;
        integer cpb_9600;
        reg [dut.baud_tick_gen_blk.ACC_WIDTH:0] rx_increment_before;
        begin
            cpb_115  = cycles_per_bit_from_sel(BAUD_SEL_115200);
            cpb_9600 = cycles_per_bit_from_sel(BAUD_SEL_9600);

            rx_send_frame(8'hD2, cpb_115, PARITY_NONE, 1'b0, 1'b1);
            rx_in = 1'b1;
            wait_rx_valid_capture(16 * cpb_115);
            #1ps;
            if (rx_data !== 8'hD2)
                fail("rx baud gate: frame 1 data mismatch");

            /*
             * This test intentionally checks the internal active increment.
             * A purely end-to-end frame check can prove the baud eventually
             * changes after rx_ack, but it cannot prove the pending-byte gate
             * held the old rate while rx_valid was still asserted.
             */
            rx_increment_before = dut.baud_tick_gen_blk.rx_increment_active;

            /* rx_valid is high; switch baud — gate must suppress the update. */
            cfg_baud_sel = BAUD_SEL_9600;
            repeat (10 * cpb_115) @(posedge clk);
            #1ps;
            if (dut.baud_tick_gen_blk.rx_increment_active !== rx_increment_before)
                fail("rx baud gate: active increment changed while rx_valid was high");

            pulse_rx_ack();
            begin : wait_baud_gate_clear
                for (ack_cycles = 0; ack_cycles < (4 * cpb_115); ack_cycles = ack_cycles + 1) begin
                    @(posedge clk);
                    #1ps;
                    if (rx_valid === 1'b0)
                        disable wait_baud_gate_clear;
                end
                fail("rx baud gate: rx_valid did not clear after rx_ack");
            end

            rx_in = 1'b1;
            /* Allow the accumulator to settle at the new rate. */
            repeat (4 * cpb_115) @(posedge clk);
            #1ps;
            if (dut.baud_tick_gen_blk.rx_increment_active === rx_increment_before)
                fail("rx baud gate: active increment did not update after rx_ack");

            /* Frame 2 at 9600 confirms the baud switch completed cleanly. */
            rx_send_and_expect_cfg(8'hD2, cpb_9600, PARITY_NONE, 1'b0, 1'b0, 1'b0, PARITY_NONE, 1'b0, 3'd0);
        end
    endtask

    initial begin
        $dumpfile("build/tb_uart_top_runtime/tb_uart_top_runtime.fst");
        $dumpvars(0, tb_uart_top_runtime);

        $display("[tb_uart_top_runtime]");

        clk        = 1'b0;
        reset      = 1'b1;
        cfg_baud_sel = BAUD_SEL_115200;
        cfg_parity = PARITY_NONE;
        rx_in      = 1'b1;
        rx_ack     = 1'b0;
        tx_start   = 1'b0;
        tx_data    = 8'h00;
        current_case = "";

        repeat (10) @(posedge clk);
        reset = 1'b0;

        /* TX: baud rate selection */

        set_case("tx baud 9600");
        cfg_baud_sel = BAUD_SEL_9600;
        cfg_parity = PARITY_NONE;
        tx_send_and_check_cfg(8'h96, cycles_per_bit_from_sel(BAUD_SEL_9600), PARITY_NONE, 1'b0, PARITY_NONE, 1'b0, 3'd0);

        set_case("tx baud 921600");
        cfg_baud_sel = BAUD_SEL_921600;
        cfg_parity = PARITY_NONE;
        tx_send_and_check_cfg(8'h69, cycles_per_bit_from_sel(BAUD_SEL_921600), PARITY_NONE, 1'b0, PARITY_NONE, 1'b0, 3'd0);

        /* TX: mid-frame config latching */

        set_case("tx parity latched mid frame");
        cfg_baud_sel = BAUD_SEL_115200;
        cfg_parity = PARITY_EVEN;
        tx_send_and_check_cfg(8'h07, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_EVEN, 1'b1, PARITY_ODD, 1'b0, 3'd0);

        set_case("tx parity next frame");
        tx_send_and_check_cfg(8'h07, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_ODD, 1'b0, PARITY_NONE, 1'b0, 3'd0);

        set_case("tx baud latched mid frame");
        cfg_baud_sel = BAUD_SEL_115200;
        cfg_parity = PARITY_NONE;
        tx_send_and_check_cfg(8'hB7, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_NONE, 1'b0, PARITY_NONE, 1'b1, BAUD_SEL_9600);

        set_case("tx baud next frame");
        tx_send_and_check_cfg(8'hB7, cycles_per_bit_from_sel(BAUD_SEL_9600), PARITY_NONE, 1'b0, PARITY_NONE, 1'b0, 3'd0);

        /* TX: frame-structure transitions (NONE <-> EVEN) */

        /* Frame 1 has no parity bit; frame 2 must gain one after the switch. */
        set_case("tx parity none to even");
        cfg_baud_sel = BAUD_SEL_115200;
        cfg_parity = PARITY_NONE;
        tx_send_and_check_cfg(8'hA5, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_NONE, 1'b0, PARITY_NONE, 1'b0, 3'd0);
        cfg_parity = PARITY_EVEN;
        /* 8'hA5: XOR=0, even parity bit = 0. */
        tx_send_and_check_cfg(8'hA5, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_EVEN, 1'b0, PARITY_NONE, 1'b0, 3'd0);

        /* Frame 1 has parity bit; frame 2 must drop it after the switch. */
        set_case("tx parity even to none");
        cfg_parity = PARITY_EVEN;
        /* 8'h3C: XOR=0, even parity bit = 0. */
        tx_send_and_check_cfg(8'h3C, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_EVEN, 1'b0, PARITY_NONE, 1'b0, 3'd0);
        cfg_parity = PARITY_NONE;
        tx_send_and_check_cfg(8'h3C, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_NONE, 1'b0, PARITY_NONE, 1'b0, 3'd0);

        /* RX: mid-frame config latching */

        set_case("rx parity latched mid frame");
        cfg_baud_sel = BAUD_SEL_115200;
        cfg_parity = PARITY_EVEN;
        /* 8'hA5: XOR=0, even parity bit = 0 (correct). Change to ODD mid-frame;
         * the latch must keep EVEN for this frame. */
        rx_send_and_expect_cfg(8'hA5, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_EVEN, 1'b0, 1'b0, 1'b1, PARITY_ODD, 1'b0, 3'd0);

        set_case("rx parity next frame");
        /* Now ODD; 8'hA5 XOR=0 so odd parity bit = 1 (correct). */
        rx_send_and_expect_cfg(8'hA5, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_ODD, 1'b1, 1'b0, 1'b0, PARITY_NONE, 1'b0, 3'd0);

        set_case("rx baud latched mid frame");
        cfg_baud_sel = BAUD_SEL_115200;
        cfg_parity = PARITY_NONE;
        rx_send_and_expect_cfg(8'h4E, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_NONE, 1'b0, 1'b0, 1'b0, PARITY_NONE, 1'b1, BAUD_SEL_9600);

        set_case("rx baud next frame");
        rx_send_and_expect_cfg(8'h4E, cycles_per_bit_from_sel(BAUD_SEL_9600), PARITY_NONE, 1'b0, 1'b0, 1'b0, PARITY_NONE, 1'b0, 3'd0);

        /* RX: error conditions */

        /* 8'hA5: XOR=0, correct even parity = 0; drive 1 to force error. */
        set_case("rx parity error");
        cfg_baud_sel = BAUD_SEL_115200;
        cfg_parity = PARITY_EVEN;
        rx_send_frame(8'hA5, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_EVEN, 1'b1, 1'b1);
        rx_check_and_ack(8'hA5, 64 * cycles_per_bit_from_sel(BAUD_SEL_115200), 1'b0, 1'b1, 1'b0);

        set_case("rx frame error");
        cfg_parity = PARITY_NONE;
        rx_send_frame(8'hC3, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_NONE, 1'b0, 1'b0);
        rx_check_and_ack(8'hC3, 64 * cycles_per_bit_from_sel(BAUD_SEL_115200), 1'b1, 1'b0, 1'b0);

        set_case("rx overrun");
        cfg_parity = PARITY_NONE;
        rx_overrun_test(cycles_per_bit_from_sel(BAUD_SEL_115200));

        /* RX: baud update gated by rx_valid */

        set_case("rx baud gate during rx_valid");
        cfg_baud_sel = BAUD_SEL_115200;
        cfg_parity = PARITY_NONE;
        rx_baud_gate_test();

        /* RX: frame-structure transitions (NONE <-> EVEN) */

        /* Frame 1 carries no parity bit; frame 2 must accept one correctly. */
        set_case("rx parity none to even");
        cfg_baud_sel = BAUD_SEL_115200;
        cfg_parity = PARITY_NONE;
        rx_send_frame(8'hA5, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_NONE, 1'b0, 1'b1);
        rx_check_and_ack(8'hA5, 64 * cycles_per_bit_from_sel(BAUD_SEL_115200), 1'b0, 1'b0, 1'b0);
        cfg_parity = PARITY_EVEN;
        /* 8'hA5: XOR=0, even parity bit = 0. */
        rx_send_frame(8'hA5, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_EVEN, 1'b0, 1'b1);
        rx_check_and_ack(8'hA5, 64 * cycles_per_bit_from_sel(BAUD_SEL_115200), 1'b0, 1'b0, 1'b0);

        /* Frame 1 carries parity bit; frame 2 must work without one. */
        set_case("rx parity even to none");
        cfg_parity = PARITY_EVEN;
        /* 8'h3C: XOR=0, even parity bit = 0. */
        rx_send_frame(8'h3C, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_EVEN, 1'b0, 1'b1);
        rx_check_and_ack(8'h3C, 64 * cycles_per_bit_from_sel(BAUD_SEL_115200), 1'b0, 1'b0, 1'b0);
        cfg_parity = PARITY_NONE;
        rx_send_frame(8'h3C, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_NONE, 1'b0, 1'b1);
        rx_check_and_ack(8'h3C, 64 * cycles_per_bit_from_sel(BAUD_SEL_115200), 1'b0, 1'b0, 1'b0);

        $display("PASS");
        $finish(0);
    end
endmodule
