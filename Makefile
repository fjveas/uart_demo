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
TB_TX_PAR := sim/tb_uart_tx_parity.v
TB_RX_PAR := sim/tb_uart_rx_parity.v
TB_TOP_PAR := sim/tb_uart_top_parity.v

UART_TX := src/hdl/uart/uart_tx.v
UART_RX := src/hdl/uart/uart_rx.v
DATA_SYNC := src/hdl/uart/data_sync.v
BAUD_GEN := src/hdl/uart/uart_baud_tick_gen.v
UART_TOP := src/hdl/uart/uart_top.v

.PHONY: all lint test tb_uart_tx tb_uart_rx tb_uart_top tb_uart_tx_parity tb_uart_rx_parity tb_uart_top_parity clean

all: test

lint:
	$(VERILATOR) --lint-only -Wall $(DATA_SYNC) $(BAUD_GEN) $(UART_RX) $(UART_TX) $(UART_TOP)

tb_uart_tx: $(BUILD_DIR)/tb_uart_tx/Vtb_uart_tx
	./$(BUILD_DIR)/tb_uart_tx/Vtb_uart_tx

tb_uart_rx: $(BUILD_DIR)/tb_uart_rx/Vtb_uart_rx
	./$(BUILD_DIR)/tb_uart_rx/Vtb_uart_rx

tb_uart_top: $(BUILD_DIR)/tb_uart_top/Vtb_uart_top
	./$(BUILD_DIR)/tb_uart_top/Vtb_uart_top

tb_uart_tx_parity: $(BUILD_DIR)/tb_uart_tx_parity/Vtb_uart_tx_parity
	./$(BUILD_DIR)/tb_uart_tx_parity/Vtb_uart_tx_parity

tb_uart_rx_parity: $(BUILD_DIR)/tb_uart_rx_parity/Vtb_uart_rx_parity
	./$(BUILD_DIR)/tb_uart_rx_parity/Vtb_uart_rx_parity

tb_uart_top_parity: $(BUILD_DIR)/tb_uart_top_parity/Vtb_uart_top_parity
	./$(BUILD_DIR)/tb_uart_top_parity/Vtb_uart_top_parity

test: lint tb_uart_tx tb_uart_rx tb_uart_top tb_uart_tx_parity tb_uart_rx_parity tb_uart_top_parity

$(BUILD_DIR)/tb_uart_tx/Vtb_uart_tx: $(TB_TX) $(UART_TX)
	mkdir -p $(BUILD_DIR)/tb_uart_tx
	$(VERILATOR) -Wall --trace-fst --binary --Mdir $(BUILD_DIR)/tb_uart_tx $(TB_TX) $(UART_TX)

$(BUILD_DIR)/tb_uart_rx/Vtb_uart_rx: $(TB_RX) $(UART_RX) $(DATA_SYNC)
	mkdir -p $(BUILD_DIR)/tb_uart_rx
	$(VERILATOR) -Wall --trace-fst --binary --Mdir $(BUILD_DIR)/tb_uart_rx $(TB_RX) $(UART_RX) $(DATA_SYNC)

$(BUILD_DIR)/tb_uart_top/Vtb_uart_top: $(TB_TOP) $(UART_TOP) $(UART_TX) $(UART_RX) $(BAUD_GEN) $(DATA_SYNC)
	mkdir -p $(BUILD_DIR)/tb_uart_top
	$(VERILATOR) -Wall --trace-fst --binary --Mdir $(BUILD_DIR)/tb_uart_top $(TB_TOP) $(UART_TOP) $(UART_TX) $(UART_RX) $(BAUD_GEN) $(DATA_SYNC)

$(BUILD_DIR)/tb_uart_tx_parity/Vtb_uart_tx_parity: $(TB_TX_PAR) $(UART_TX)
	mkdir -p $(BUILD_DIR)/tb_uart_tx_parity
	$(VERILATOR) -Wall --trace-fst --binary --Mdir $(BUILD_DIR)/tb_uart_tx_parity $(TB_TX_PAR) $(UART_TX)

$(BUILD_DIR)/tb_uart_rx_parity/Vtb_uart_rx_parity: $(TB_RX_PAR) $(UART_RX) $(DATA_SYNC)
	mkdir -p $(BUILD_DIR)/tb_uart_rx_parity
	$(VERILATOR) -Wall --trace-fst --binary --Mdir $(BUILD_DIR)/tb_uart_rx_parity $(TB_RX_PAR) $(UART_RX) $(DATA_SYNC)

$(BUILD_DIR)/tb_uart_top_parity/Vtb_uart_top_parity: $(TB_TOP_PAR) $(UART_TOP) $(UART_TX) $(UART_RX) $(BAUD_GEN) $(DATA_SYNC)
	mkdir -p $(BUILD_DIR)/tb_uart_top_parity
	$(VERILATOR) -Wall --trace-fst --binary --Mdir $(BUILD_DIR)/tb_uart_top_parity $(TB_TOP_PAR) $(UART_TOP) $(UART_TX) $(UART_RX) $(BAUD_GEN) $(DATA_SYNC)

clean:
	rm -rf $(BUILD_DIR)
