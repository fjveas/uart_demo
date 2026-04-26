# Using `uart_top`

`uart_top` is the integration point for designs where baud rate and parity are
fixed at synthesis time. It wraps the transmitter, receiver, and baud tick
generators behind a byte-oriented interface.

Use it when you want:

- 8-bit UART transmit and receive
- optional even or odd parity
- stop-bit framing error detection
- parity error detection
- overrun detection
- a held `valid/ack` receive interface
- baud rate and parity determined at synthesis, not at runtime

Use `uart_top_runtime` instead when software or control logic needs to change
baud rate or parity while the FPGA is running. See
[using_uart_top_runtime.md](using_uart_top_runtime.md).

## Parameters

```verilog
uart_top #(
    .CLK_FREQUENCY(100000000),
    .BAUD_RATE(115200),
    .PARITY(0)
) uart_inst (...);
```

| Parameter | Description |
|-----------|-------------|
| `CLK_FREQUENCY` | Input clock frequency in Hz |
| `BAUD_RATE` | UART baud rate in symbols per second |
| `PARITY` | `0=none`, `1=even`, `2=odd` |

`PARITY=0` gives the default 8N1 configuration.

## Ports

### Clock and reset

```verilog
input clk,
input reset,
```

`reset` is active-high and synchronous to `clk`.

### Serial lines

```verilog
input  rx,
output tx,
```

UART lines are idle-high. The external asynchronous RX pin can be connected
directly to `rx`; `uart_rx` instantiates `data_sync` internally.

### Transmit interface

```verilog
input        tx_start,
input  [7:0] tx_data,
output       tx_busy,
```

`tx_start` requests transmission of `tx_data`. Pulse it for one `clk` cycle
while `tx_busy` is low. `tx_data` is latched when the frame starts, so later
changes do not affect the active frame.

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

When `rx_valid` is high, `rx_data` and the status flags hold one receive result.
They remain stable until the consumer pulses `rx_ack` for one `clk` cycle.

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

When `PARITY=0`, `rx_parity_error` stays low.

## Minimal instantiation

```verilog
wire [7:0] rx_data;
wire       rx_valid;
wire       rx_frame_error;
wire       rx_parity_error;
wire       rx_overrun;
wire       tx_busy;

reg        tx_start;
reg  [7:0] tx_data;
reg        rx_ack;

uart_top #(
    .CLK_FREQUENCY(100000000),
    .BAUD_RATE(115200),
    .PARITY(0)
) uart_inst (
    .clk(clk),
    .reset(reset),
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

## Common configurations

### 8N1

```verilog
.BAUD_RATE(115200),
.PARITY(0)
```

### 8E1

```verilog
.BAUD_RATE(115200),
.PARITY(1)
```

### 8O1

```verilog
.BAUD_RATE(115200),
.PARITY(2)
```

## Integration checklist

- Wait for `tx_busy == 0` before pulsing `tx_start`.
- Keep `tx_start` to a one-cycle pulse.
- Treat `rx_valid` as a held result, not a one-cycle pulse.
- Read `rx_data` and all status flags before asserting `rx_ack`.
- Pulse `rx_ack` for one clock cycle after consuming a received byte.
- `BAUD_RATE` and `PARITY` are synthesis-time constants; do not expect to change them at runtime.

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
| `sim/tb_uart_tx.v` | TX framing and busy behavior |
| `sim/tb_uart_rx.v` | RX framing, glitch filtering, errors, overrun |
| `sim/tb_uart_top.v` | Full wrapper integration in 8N1 mode |
| `sim/tb_uart_tx_parity.v` | TX parity generation |
| `sim/tb_uart_rx_parity.v` | RX parity checking |
| `sim/tb_uart_top_parity.v` | Wrapper-level parity behavior |
