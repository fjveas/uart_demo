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

TB_TX := sim/tb_uart_tx.v
TB_RX := sim/tb_uart_rx.v

UART_TX := src/hdl/uart/uart_tx.v
UART_RX := src/hdl/uart/uart_rx.v
DATA_SYNC := src/hdl/uart/data_sync.v
BAUD_GEN := src/hdl/uart/uart_baud_tick_gen.v
UART_BASIC := src/hdl/uart/uart_basic.v

.PHONY: all lint test tb_uart_tx tb_uart_rx clean

all: test

lint:
	$(VERILATOR) --lint-only -Wall $(DATA_SYNC) $(BAUD_GEN) $(UART_RX) $(UART_TX) $(UART_BASIC)

tb_uart_tx: $(BUILD_DIR)/tb_uart_tx/Vtb_uart_tx
	./$(BUILD_DIR)/tb_uart_tx/Vtb_uart_tx

tb_uart_rx: $(BUILD_DIR)/tb_uart_rx/Vtb_uart_rx
	./$(BUILD_DIR)/tb_uart_rx/Vtb_uart_rx

test: lint tb_uart_tx tb_uart_rx

$(BUILD_DIR)/tb_uart_tx/Vtb_uart_tx: $(TB_TX) $(UART_TX)
	mkdir -p $(BUILD_DIR)/tb_uart_tx
	$(VERILATOR) -Wall --binary --Mdir $(BUILD_DIR)/tb_uart_tx $(TB_TX) $(UART_TX)

$(BUILD_DIR)/tb_uart_rx/Vtb_uart_rx: $(TB_RX) $(UART_RX) $(DATA_SYNC)
	mkdir -p $(BUILD_DIR)/tb_uart_rx
	$(VERILATOR) -Wall --binary --Mdir $(BUILD_DIR)/tb_uart_rx $(TB_RX) $(UART_RX) $(DATA_SYNC)

clean:
	rm -rf $(BUILD_DIR)

