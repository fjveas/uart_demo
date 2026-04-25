# UART demo Makefile (Verilator-focused)
#
# Common targets:
#   make lint
#   make test
#   make clean
#
# Notes:
# - Uses Verilator's `--binary` flow for quick compile+run of pure-Verilog testbenches.
# - Keeps build output in per-test directories under `build/`.

SHELL := /bin/sh

VERILATOR ?= verilator

BUILD_DIR := build

TB_TX     := sim/tb_uart_tx.v
TB_RX     := sim/tb_uart_rx.v
TB_TOP    := sim/tb_uart_top.v
TB_TOP_RT := sim/tb_uart_top_runtime.v
TB_TX_PAR := sim/tb_uart_tx_parity.v
TB_RX_PAR := sim/tb_uart_rx_parity.v
TB_TOP_PAR := sim/tb_uart_top_parity.v

UART_TX := src/hdl/uart/uart_tx.v
UART_RX := src/hdl/uart/uart_rx.v
DATA_SYNC := src/hdl/uart/data_sync.v
BAUD_GEN := src/hdl/uart/uart_baud_tick_gen.v
RUNTIME_BAUD_GEN := src/hdl/uart/uart_runtime_baud_tick_gen.v
UART_TOP := src/hdl/uart/uart_top.v
UART_TOP_RUNTIME := src/hdl/uart/uart_top_runtime.v

.PHONY: all lint test tb_uart_tx tb_uart_rx tb_uart_top tb_uart_top_runtime tb_uart_tx_parity tb_uart_rx_parity tb_uart_top_parity clean

all: test

lint:
	$(VERILATOR) --lint-only -Wall --top-module uart_top $(DATA_SYNC) $(BAUD_GEN) $(UART_RX) $(UART_TX) $(UART_TOP)
	$(VERILATOR) --lint-only -Wall --top-module uart_top_runtime $(DATA_SYNC) $(RUNTIME_BAUD_GEN) $(UART_RX) $(UART_TX) $(UART_TOP_RUNTIME)

tb_uart_tx: $(BUILD_DIR)/tb_uart_tx/Vtb_uart_tx
	./$(BUILD_DIR)/tb_uart_tx/Vtb_uart_tx

tb_uart_rx: $(BUILD_DIR)/tb_uart_rx/Vtb_uart_rx
	./$(BUILD_DIR)/tb_uart_rx/Vtb_uart_rx

tb_uart_top: $(BUILD_DIR)/tb_uart_top/Vtb_uart_top
	./$(BUILD_DIR)/tb_uart_top/Vtb_uart_top

tb_uart_top_runtime: $(BUILD_DIR)/tb_uart_top_runtime/Vtb_uart_top_runtime
	./$(BUILD_DIR)/tb_uart_top_runtime/Vtb_uart_top_runtime

tb_uart_tx_parity: $(BUILD_DIR)/tb_uart_tx_parity/Vtb_uart_tx_parity
	./$(BUILD_DIR)/tb_uart_tx_parity/Vtb_uart_tx_parity

tb_uart_rx_parity: $(BUILD_DIR)/tb_uart_rx_parity/Vtb_uart_rx_parity
	./$(BUILD_DIR)/tb_uart_rx_parity/Vtb_uart_rx_parity

tb_uart_top_parity: $(BUILD_DIR)/tb_uart_top_parity/Vtb_uart_top_parity
	./$(BUILD_DIR)/tb_uart_top_parity/Vtb_uart_top_parity

test: lint tb_uart_tx tb_uart_rx tb_uart_top tb_uart_top_runtime tb_uart_tx_parity tb_uart_rx_parity tb_uart_top_parity

$(BUILD_DIR)/tb_uart_tx/Vtb_uart_tx: $(TB_TX) $(UART_TX)
	mkdir -p $(BUILD_DIR)/tb_uart_tx
	$(VERILATOR) -Wall --trace-fst --binary --top-module tb_uart_tx --Mdir $(BUILD_DIR)/tb_uart_tx $(TB_TX) $(UART_TX)

$(BUILD_DIR)/tb_uart_rx/Vtb_uart_rx: $(TB_RX) $(UART_RX) $(DATA_SYNC)
	mkdir -p $(BUILD_DIR)/tb_uart_rx
	$(VERILATOR) -Wall --trace-fst --binary --top-module tb_uart_rx --Mdir $(BUILD_DIR)/tb_uart_rx $(TB_RX) $(UART_RX) $(DATA_SYNC)

$(BUILD_DIR)/tb_uart_top/Vtb_uart_top: $(TB_TOP) $(UART_TOP) $(UART_TX) $(UART_RX) $(BAUD_GEN) $(DATA_SYNC)
	mkdir -p $(BUILD_DIR)/tb_uart_top
	$(VERILATOR) -Wall --trace-fst --binary --top-module tb_uart_top --Mdir $(BUILD_DIR)/tb_uart_top $(TB_TOP) $(UART_TOP) $(UART_TX) $(UART_RX) $(BAUD_GEN) $(DATA_SYNC)

$(BUILD_DIR)/tb_uart_top_runtime/Vtb_uart_top_runtime: $(TB_TOP_RT) $(UART_TOP_RUNTIME) $(RUNTIME_BAUD_GEN) $(UART_TX) $(UART_RX) $(DATA_SYNC)
	mkdir -p $(BUILD_DIR)/tb_uart_top_runtime
	$(VERILATOR) -Wall --trace-fst --binary --top-module tb_uart_top_runtime --Mdir $(BUILD_DIR)/tb_uart_top_runtime $(TB_TOP_RT) $(UART_TOP_RUNTIME) $(RUNTIME_BAUD_GEN) $(UART_TX) $(UART_RX) $(DATA_SYNC)

$(BUILD_DIR)/tb_uart_tx_parity/Vtb_uart_tx_parity: $(TB_TX_PAR) $(UART_TX)
	mkdir -p $(BUILD_DIR)/tb_uart_tx_parity
	$(VERILATOR) -Wall --trace-fst --binary --top-module tb_uart_tx_parity --Mdir $(BUILD_DIR)/tb_uart_tx_parity $(TB_TX_PAR) $(UART_TX)

$(BUILD_DIR)/tb_uart_rx_parity/Vtb_uart_rx_parity: $(TB_RX_PAR) $(UART_RX) $(DATA_SYNC)
	mkdir -p $(BUILD_DIR)/tb_uart_rx_parity
	$(VERILATOR) -Wall --trace-fst --binary --top-module tb_uart_rx_parity --Mdir $(BUILD_DIR)/tb_uart_rx_parity $(TB_RX_PAR) $(UART_RX) $(DATA_SYNC)

$(BUILD_DIR)/tb_uart_top_parity/Vtb_uart_top_parity: $(TB_TOP_PAR) $(UART_TOP) $(UART_TX) $(UART_RX) $(BAUD_GEN) $(DATA_SYNC)
	mkdir -p $(BUILD_DIR)/tb_uart_top_parity
	$(VERILATOR) -Wall --trace-fst --binary --top-module tb_uart_top_parity --Mdir $(BUILD_DIR)/tb_uart_top_parity $(TB_TOP_PAR) $(UART_TOP) $(UART_TX) $(UART_RX) $(BAUD_GEN) $(DATA_SYNC)

clean:
	rm -rf $(BUILD_DIR)
