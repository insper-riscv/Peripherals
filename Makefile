SHELL := /bin/bash
GHDL  := ghdl
STD   := --std=08
WDIR  := build/ghdl

# The peripherals use the blocks of Common-Components, cloned next to this repository.
VHDL      := $(shell find GPIO TIMER UART tests/vhdl -name '*.vhd' | sort) $(sort $(wildcard ../Common-Components/src/*.vhd))

.PHONY: check test paths clean

# GHDL syntax check of every source, in dependency order (riscv-tools vhdl-sort).
check:
	@mkdir -p $(WDIR)
	@$(GHDL) -a $(STD) --work=work --workdir=$(WDIR) $$(uv run riscv-tools vhdl-sort $(VHDL))
	@echo "VHDL syntax check passed"

# Per-entity cocotb tests; `make test TEST=GPIO` for one entry of tests/python/tests.json.
test:
	uv run python tests/python/runner.py $(TEST)

# Every path the configuration lists exists.
paths:
	uv run riscv-tools --root . check-paths --manifest paths.yaml

clean:
	rm -rf build
	find . -type f \( -name '*.vcd' -o -name '*.ghw' \) -print -delete
