SHELL := /bin/bash
GHDL  := ghdl
STD   := --std=08
WDIR  := build/ghdl

# The peripherals use the blocks of Common-Components, included as a submodule in src/common. The Quartus
# shells of src/*/cyclone-v/ need Intel's megafunctions, which the toolchain image does not carry.
VHDL      := $(shell find src tests/vhdl -name '*.vhd' -not -path 'src/common/*' -not -path '*/cyclone-v/*' | sort) $(sort $(wildcard src/common/src/*.vhd))

.PHONY: check test usb-driver-test paths formal clean

# GHDL syntax check of every source, in dependency order (riscv-tools vhdl-sort).
check:
	@mkdir -p $(WDIR)
	@$(GHDL) -a $(STD) --work=work --workdir=$(WDIR) $$(riscv-tools vhdl-sort $(VHDL))
	@echo "VHDL syntax check passed"

# Per-entity cocotb tests; `make test TEST=GPIO` for one entry of tests/python/tests.json.
test: usb-driver-test
	uv run python tests/python/runner.py $(TEST)

# Every path the configuration lists exists.
paths:
	riscv-tools --root . check-paths --manifest paths.yaml
	riscv-tools --root . check-tree --kind peripherals

# Formal proofs (SymbiYosys and one engine of the CI image: FORMAL_ENGINE is yices, bitwuzla, boolector or
# abc-bmc3): the proofs of the timer (with its prescaler, overflow detector and comparator), the GPIO cell and
# the UART, with their mutants. The result of the run is build/formal/result-<engine>.tsv.
FORMAL_ENGINE ?= bitwuzla
formal:
	FORMAL_ENGINE=$(FORMAL_ENGINE) bash formal/run.sh

clean:
	rm -rf build
	find . -type f \( -name '*.vcd' -o -name '*.ghw' \) -print -delete

# USB driver on the host against the C model of the bridge and the chip (tests/c/usb_hpi.c).
USB_DRIVER_DIR := src/USB/soc/driver/c
usb-driver-test:
	@mkdir -p build/drivers
	$(CC) -std=c23 -Wall -Wextra -Wpedantic -Werror -Wconversion -Wshadow -DRV32_USB_MMIO_HOOK -I$(USB_DRIVER_DIR) $(USB_DRIVER_DIR)/rv32_usb.c $(USB_DRIVER_DIR)/rv32_usb_unverified.c tests/c/usb_hpi.c -o build/drivers/usb_hpi
	@build/drivers/usb_hpi
