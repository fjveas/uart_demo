# Using `uart_top_runtime`

`uart_top_runtime` is the integration point for designs where baud rate and
parity need to change while the FPGA is running. It exposes the same byte
interface as `uart_top` but replaces the compile-time `BAUD_RATE` and `PARITY`
parameters with synchronous configuration inputs.

Use it when you want:

- runtime-selectable baud rate (9600 to 921600)
- runtime-selectable parity (none, even, odd)
- the same held `valid/ack` receive interface as `uart_top`
- configuration driven by software, a register interface, or front-panel switches

Use `uart_top` instead when baud rate and parity are fixed for the life of the
design. See [using_uart_top.md](using_uart_top.md).

## Parameters

```verilog
uart_top_runtime #(
    .CLK_FREQUENCY(100000000),
    .MIN_BAUD_RATE(9600)
) uart_inst (...);
```

| Parameter | Description |
|-----------|-------------|
| `CLK_FREQUENCY` | Input clock frequency in Hz |
| `MIN_BAUD_RATE` | Lowest baud rate reachable via `cfg_baud_sel`; sizes the accumulator |

`MIN_BAUD_RATE` affects only the accumulator width inside the baud generator.
If you add entries below 9600 to `cfg_baud_sel`, lower `MIN_BAUD_RATE`
accordingly so the accumulator does not overflow.

## Ports

### Clock and reset

```verilog
input clk,
input reset,
```

`reset` is active-high and synchronous to `clk`.

### Configuration inputs

```verilog
input [2:0] cfg_baud_sel,
input [1:0] cfg_parity,
```

Both signals must be synchronous to `clk`. If they originate from switches,
another clock domain, or an asynchronous register bus, synchronize or register
them before connecting here; the design does not re-synchronize these inputs
internally.

#### `cfg_baud_sel` encoding

| Value | Baud rate |
|-------|-----------|
| `3'd0` | 9600 |
| `3'd1` | 19200 |
| `3'd2` | 38400 |
| `3'd3` | 57600 |
| `3'd4` | 115200 |
| `3'd5` | 230400 |
| `3'd6` | 460800 |
| `3'd7` | 921600 |

#### `cfg_parity` encoding

| Value | Mode |
|-------|------|
| `2'd0` | None (8N1) |
| `2'd1` | Even (8E1) |
| `2'd2` | Odd (8O1) |

### Serial lines

```verilog
input  rx,
output tx,
```

UART lines are idle-high. The external asynchronous RX pin can be connected
directly to `rx`; the receiver instantiates `data_sync` internally.

### Transmit interface

```verilog
input        tx_start,
input  [7:0] tx_data,
output       tx_busy,
```

Identical to `uart_top`. Pulse `tx_start` for one cycle while `tx_busy` is low.
`tx_data` is latched when the frame starts.

Typical transmit pattern:

```verilog
always @(posedge clk) begin
    if (reset) begin
        tx_start <= 1'b0;
        tx_data  <= 8'h00;
    end else begin
        tx_start <= 1'b0;

        if (!tx_busy) begin
            tx_data  <= 8'h55;
            tx_start <= 1'b1;
        end
    end
end
```

### Receive interface

```verilog
output [7:0] rx_data,
output       rx_valid,
output       rx_frame_error,
output       rx_parity_error,
output       rx_overrun,
input        rx_ack,
```

Identical to `uart_top`. When `rx_valid` is high, `rx_data` and the status
flags hold one receive result and remain stable until the consumer pulses
`rx_ack` for one `clk` cycle.

Typical receive pattern:

```verilog
always @(posedge clk) begin
    if (reset) begin
        rx_ack <= 1'b0;
    end else begin
        rx_ack <= 1'b0;

        if (rx_valid) begin
            /* Read rx_data and status flags here. */
            rx_ack <= 1'b1;
        end
    end
end
```

The RX status flags are meaningful only while `rx_valid` is high:

| Signal | Meaning |
|--------|---------|
| `rx_frame_error` | Stop bit was low when it should have been high |
| `rx_parity_error` | Received parity bit did not match the expected value |
| `rx_overrun` | A new start edge arrived before the previous byte was acknowledged |

## When configuration changes take effect

Changes to `cfg_baud_sel` and `cfg_parity` are not applied immediately. The
design delays each update to a safe frame boundary so that an in-progress frame
is never corrupted mid-stream.

| Signal | When the new value takes effect |
|--------|---------------------------------|
| `cfg_parity` (TX) | When the next `tx_start` is accepted and the frame begins |
| `cfg_parity` (RX) | After the start bit of the next incoming frame is confirmed |
| `cfg_baud_sel` (TX) | When the transmitter returns to idle between frames |
| `cfg_baud_sel` (RX) | When the receiver is fully idle: no frame in progress and no byte waiting for `rx_ack` |

The last rule means that if `rx_valid` is high and a byte is waiting to be
acknowledged, a baud rate change will not take effect until after `rx_ack` is
asserted. This prevents a rate switch from disrupting the accumulator phase
while the receiver is in the ready state.

## Minimal instantiation

```verilog
wire [7:0] rx_data;
wire       rx_valid;
wire       rx_frame_error;
wire       rx_parity_error;
wire       rx_overrun;
wire       tx_busy;

reg  [2:0] cfg_baud_sel;
reg  [1:0] cfg_parity;
reg        tx_start;
reg  [7:0] tx_data;
reg        rx_ack;

uart_top_runtime #(
    .CLK_FREQUENCY(100000000),
    .MIN_BAUD_RATE(9600)
) uart_inst (
    .clk(clk),
    .reset(reset),
    .cfg_baud_sel(cfg_baud_sel),
    .cfg_parity(cfg_parity),
    .rx(uart_rx_pin),
    .rx_data(rx_data),
    .rx_valid(rx_valid),
    .rx_frame_error(rx_frame_error),
    .rx_parity_error(rx_parity_error),
    .rx_overrun(rx_overrun),
    .rx_ack(rx_ack),
    .tx(uart_tx_pin),
    .tx_start(tx_start),
    .tx_data(tx_data),
    .tx_busy(tx_busy)
);
```

## Integration checklist

- Wait for `tx_busy == 0` before pulsing `tx_start`.
- Keep `tx_start` to a one-cycle pulse.
- Treat `rx_valid` as a held result, not a one-cycle pulse.
- Read `rx_data` and all status flags before asserting `rx_ack`.
- Pulse `rx_ack` for one clock cycle after consuming a received byte.
- Synchronize `cfg_baud_sel` and `cfg_parity` to `clk` before connecting them if they come from an asynchronous source.
- Do not change `cfg_baud_sel` or `cfg_parity` mid-frame and expect the current frame to reflect the new value; changes take effect at the next frame boundary.
- Acknowledge pending bytes promptly if a baud rate change is time-sensitive; the RX baud update is gated until `rx_valid` clears.

## Verification

Run the full Verilator suite from the repo root:

```sh
make test
```

Run lint explicitly when changing RTL:

```sh
make lint
```

Relevant testbenches:

| Testbench | Covers |
|-----------|--------|
| `sim/tb_uart_top_runtime.v` | Baud selection, mid-frame latching, frame-structure transitions, parity error, frame error, overrun, baud gate on `rx_valid` |
| `sim/tb_uart_tx.v` | TX framing and busy behavior (shared core) |
| `sim/tb_uart_rx.v` | RX framing, glitch filtering, errors, overrun (shared core) |
