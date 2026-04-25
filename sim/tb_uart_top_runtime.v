/*
 * tb_uart_top_runtime.v
 *
 * Integration testbench focused on uart_top_runtime:
 * - baud selection changes while idle
 * - parity mode changes while idle
 * - parity and baud changes during active frames are deferred
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
            begin : wait_loop
                for (i = 0; i < timeout_cycles; i = i + 1) begin
                    @(posedge clk);
                    #1ps;
                    if (tx == 1'b0) begin
                        start_seen = 1'b1;
                        disable wait_loop;
                    end
                end
            end
            if (!start_seen)
                fail("Timed out waiting for TX start bit");
        end
    endtask

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

    task automatic wait_rx_valid_capture(input integer timeout_cycles);
        integer i;
        reg valid_seen;
        begin
            valid_seen = 1'b0;
            begin : wait_loop
                for (i = 0; i < timeout_cycles; i = i + 1) begin
                    @(posedge clk);
                    #1ps;
                    if (rx_valid) begin
                        valid_seen = 1'b1;
                        disable wait_loop;
                    end
                end
            end
            if (!valid_seen)
                fail("Timed out waiting for rx_valid");
        end
    endtask

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
            begin : wait_clear
                for (ack_cycles = 0; ack_cycles < (2 * cycles_per_bit); ack_cycles = ack_cycles + 1) begin
                    @(posedge clk);
                    #1ps;
                    if (rx_valid === 1'b0)
                        disable wait_clear;
                end
                fail("rx_valid did not clear after rx_ack");
            end

            rx_in = 1'b1;
            repeat (2 * cycles_per_bit) @(posedge clk);
        end
    endtask

    initial begin
        $dumpfile("build/tb_uart_top_runtime/tb_uart_top_runtime.fst");
        $dumpvars(0, tb_uart_top_runtime);

        $display("[tb_uart_top_runtime]");

        clk = 1'b0;
        reset = 1'b1;
        cfg_baud_sel = BAUD_SEL_115200;
        cfg_parity = PARITY_NONE;
        rx_in = 1'b1;
        rx_ack = 1'b0;
        tx_start = 1'b0;
        tx_data = 8'h00;
        current_case = "";

        repeat (10) @(posedge clk);
        reset = 1'b0;

        set_case("tx baud 9600");
        cfg_baud_sel = BAUD_SEL_9600;
        cfg_parity = PARITY_NONE;
        tx_send_and_check_cfg(8'h96, cycles_per_bit_from_sel(BAUD_SEL_9600), PARITY_NONE, 1'b0, PARITY_NONE, 1'b0, 3'd0);

        set_case("tx baud 921600");
        cfg_baud_sel = BAUD_SEL_921600;
        cfg_parity = PARITY_NONE;
        tx_send_and_check_cfg(8'h69, cycles_per_bit_from_sel(BAUD_SEL_921600), PARITY_NONE, 1'b0, PARITY_NONE, 1'b0, 3'd0);

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

        set_case("rx parity latched mid frame");
        cfg_baud_sel = BAUD_SEL_115200;
        cfg_parity = PARITY_EVEN;
        rx_send_and_expect_cfg(8'hA5, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_EVEN, 1'b0, 1'b0, 1'b1, PARITY_ODD, 1'b0, 3'd0);

        set_case("rx parity next frame");
        rx_send_and_expect_cfg(8'hA5, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_ODD, 1'b1, 1'b0, 1'b0, PARITY_NONE, 1'b0, 3'd0);

        set_case("rx baud latched mid frame");
        cfg_baud_sel = BAUD_SEL_115200;
        cfg_parity = PARITY_NONE;
        rx_send_and_expect_cfg(8'h4E, cycles_per_bit_from_sel(BAUD_SEL_115200), PARITY_NONE, 1'b0, 1'b0, 1'b0, PARITY_NONE, 1'b1, BAUD_SEL_9600);

        set_case("rx baud next frame");
        rx_send_and_expect_cfg(8'h4E, cycles_per_bit_from_sel(BAUD_SEL_9600), PARITY_NONE, 1'b0, 1'b0, 1'b0, PARITY_NONE, 1'b0, 3'd0);

        $display("PASS");
        $finish(0);
    end
endmodule
